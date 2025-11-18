#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    [ -f "${0}" ] && rm -- "${0}"
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# remove all other debian kernels
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt remove 'linux-image-*'

# remove os-prober if present
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt remove os-prober || true

# apply the new settings to grub
update-grub

# one bridge per interface, dhcp setup on first device
tee /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
EOF
cnt=$((-1))
ip -j link show | jq -r '.[] | select(.link_type != "loopback" and (.ifname | startswith("vmbr") | not)) | .ifname' | while read -r line; do
cnt=$((cnt+1))
tee -a /etc/network/interfaces <<EOF

iface $line inet manual

auto vmbr$cnt
iface vmbr$cnt inet $(if [ $cnt -eq 0 ]; then echo "dhcp"; else echo "manual"; fi)
    bridge-ports $line
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
    post-up resolvectl mdns vmbr$cnt yes
EOF
done

# one internal bridge for private networks
tee -a /etc/network/interfaces <<EOF

auto vmbrlan0
iface vmbrlan0 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
    post-up resolvectl mdns vmbrlan0 yes
EOF

# switch from networkd to ifupdown2
systemctl stop systemd-networkd{.service,.socket}
systemctl mask systemd-networkd{.service,.socket}
ifreload -a

# Set hostname in etc/hosts
FQDNAME=$(</etc/hostname)
HOSTNAME=${FQDNAME%%.*}
tee /tmp/hosts_columns <<EOF
# IPv4/v6|FQDN|HOSTNAME
127.0.0.1|$FQDNAME|$HOSTNAME
::1|$FQDNAME|$HOSTNAME
127.0.0.1|localhost.internal|localhost
::1|localhost.internal|localhost
EOF
ip -f inet addr | awk '/inet / {print $2}' | cut -d'/' -f1 | while read -r PUB_IP_ADDR; do
tee -a /tmp/hosts_columns <<EOF
$PUB_IP_ADDR|$FQDNAME|$HOSTNAME
EOF
done
tee /etc/hosts <<EOF
# Static table lookup for hostnames.
# See hosts(5) for details.

# https://www.icann.org/en/public-comment/proceeding/proposed-top-level-domain-string-for-private-use-24-01-2024
$(column /tmp/hosts_columns -t -s '|')
EOF
rm /tmp/hosts_columns

# create proxmox groups
pveum group add admins
pveum group add users

# create local admin pveadm
USERID=pveadm
USERHASH=$(openssl passwd -6 -salt abcxyz "${USERID}")
useradd -m -r -s /bin/bash "$USERID"
sed -i 's/^'"$USERID"':[^:]*:/'"$USERID"':'"${USERHASH//\//\\/}"':/' /etc/shadow

# add permissions to groups and pools
pveum acl modify / --roles Administrator -groups admins -propagate 1
pveum acl modify /mapping --roles PVEMappingUser -groups users -propagate 1
ip -j link show | jq -r '.[] | select(.link_type != "loopback" and (.ifname | startswith("vmbr"))) | .ifname' | while read -r line; do
  pveum acl modify /sdn/zones/localnetwork/$line --roles PVESDNUser -groups users -propagate 1
done
pveum acl modify /storage --roles PVEDatastoreUser -groups users -propagate 1

# add local admins to group admins
for username in root pveadm; do
  pveum user add "$username"@pam || true
  pveum user modify "$username"@pam -groups admins || true
done

# add local users to group users
getent passwd | while IFS=: read -r username x uid gid gecos home shell; do
  if [ -n "$home" ] && [ -d "$home" ] && [ "${home:0:6}" == "/home/" ]; then
    if [ "$uid" -ge 1000 ]; then
      pveum user add "$username"@pam || true
      pveum user modify "$username"@pam -groups users || true
    fi
  fi
done

# create first pool pool0
pveum pool add pool0 || true
pveum acl modify /pool/pool0 --roles PVEPoolUser,PVETemplateUser -groups users -propagate 1 || true

# create user pools and vlans
pveum user list -full | grep " users " | cut -d' ' -f2 | while read -r username; do
  poolname=$(echo -en "pool-$username" | cut -d'@' -f1)
  pveum pool add "$poolname" || true
  pveum acl modify "/pool/$poolname" --roles PVEAdmin -users "$username" -propagate 1 || true
  brname=$(echo -en "br$username" | cut -d'@' -f1)
  if ! grep -qE "$brname" /etc/network/interfaces; then
    tee -a /etc/network/interfaces <<EOF

auto $brname
iface $brname inet static
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
    post-up resolvectl mdns $brname yes
EOF
  fi
  pveum acl modify "/sdn/zones/localnetwork/$brname" --roles PVESDNUser -users "$username" -propagate 1 || true
done

# Scheduled task to update all users and pools on a daily basis
tee /usr/local/bin/update-all-users.sh <<'EOF'
#!/usr/bin/env bash
# update all users in @pam

# add local users to group users
getent passwd | while IFS=: read -r username x uid gid gecos home shell; do
  if [ -n "$home" ] && [ -d "$home" ] && [ "${home:0:6}" == "/home/" ]; then
    if [ "$uid" -ge 1000 ]; then
      pveum user add "$username"@pam || true
      pveum user modify "$username"@pam -groups users || true
    fi
  fi
done

# create one pool per user
pveum user list -full | grep " users " | cut -d' ' -f2 | while read -r username; do
  poolname=$(echo -en "pool-$username" | cut -d'@' -f1)
  pveum pool add "$poolname" || true
  pveum acl modify "/pool/$poolname" --roles PVEAdmin -users "$username" -propagate 1 || true
  brname=$(echo -en "br$username" | cut -d'@' -f1)
  if ! grep -qE "$brname" /etc/network/interfaces; then
    tee -a /etc/network/interfaces <<EOX

auto $brname
iface $brname inet static
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
    post-up resolvectl mdns $brname yes
EOX
  fi
  pveum acl modify "/sdn/zones/localnetwork/$brname" --roles PVESDNUser -users "$username" -propagate 1 || true
done
EOF
chmod +x /usr/local/bin/update-all-users.sh
tee /etc/systemd/system/update-all-users.service <<EOF
[Unit]
Description=Update all LXC containers

[Service]
Type=simple
StandardInput=null
StandardOutput=journal
StandardError=journal
ExecStart=/usr/local/bin/update-all-users.sh
EOF
tee /etc/systemd/system/update-all-users.timer <<EOF
[Unit]
Description=Scheduled update of all LXC containers

[Timer]
OnCalendar=*-*-* 02:17

[Install]
WantedBy=multi-user.target
EOF
systemctl enable update-all-users.timer

# create custom x86-64-v3 profiles
mkdir -p /etc/pve/virtual-guest
tee /etc/pve/virtual-guest/cpu-models.conf <<EOF
cpu-model: x86-64-v3-nested-intel
    flags +vmx;+aes;+popcnt;+pni;+sse4.1;+sse4.2;+ssse3;+avx;+avx2;+bmi1;+bmi2;+f16c;+fma;+abm;+movbe;+xsave
    reported-model qemu64

cpu-model: x86-64-v3-nested-amd
    flags +svm;+aes;+popcnt;+pni;+sse4.1;+sse4.2;+ssse3;+avx;+avx2;+bmi1;+bmi2;+f16c;+fma;+abm;+movbe;+xsave
    reported-model qemu64
EOF

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
