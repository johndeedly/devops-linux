#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    [ -f "${0}" ] && rm -- "${0}"
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# https://www.tecmint.com/install-proxmox/
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install curl apt-transport-https ca-certificates gnupg2

# install the proxmox repository key
echo ":: download proxmox repository certificate"
(
  source /etc/os-release
  curl -fsSL "https://enterprise.proxmox.com/debian/proxmox-release-${VERSION_CODENAME}.gpg" | gpg --dearmor -o "/etc/apt/trusted.gpg.d/proxmox-release-${VERSION_CODENAME}.gpg"
)

# add the proxmox repository to the package sources
(
  source /etc/os-release
  tee /etc/apt/sources.list.d/pve-install-repo.list <<EOF
deb [arch=amd64] http://download.proxmox.com/debian/pve ${VERSION_CODENAME} pve-no-subscription
EOF
)

# install the packer repository key
echo ":: download packer repository certificate"
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/hashicorp-archive-keyring.gpg

# add the packer repository to the package sources
(
  source /etc/os-release
  tee /etc/apt/sources.list.d/hashicorp.list <<EOF
deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main
EOF
)

# removes the nagging "subscription missing" popup on login (permanent solution)
tee /etc/apt/apt.conf.d/90-no-more-nagging <<EOF
DPkg::Post-Invoke { "/usr/local/sbin/no_more_nagging"; };
EOF
tee /usr/local/sbin/no_more_nagging <<EOF
#!/usr/bin/env bash
if [ -f /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js ]; then
  sed -i 's|\(checked_command: function\)|//replace-me-nag\n\1|' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
  sed -i '/checked_command: function/,/^$/d' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
  sed -i 's|//replace-me-nag|checked_command: function (orig_cmd) { orig_cmd(); },\n|' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
fi
EOF
chmod +x /usr/local/sbin/no_more_nagging

# update and upgrade
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt update
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt full-upgrade

# preconfigure grub-pc (otherwise it won't allow noninteractive)
debconf-set-selections <<EOF
grub-pc grub-pc/install_devices multiselect $(lsblk -no MOUNTPOINT,PKNAME | sed -e '/^\/ /!d' | head -n 1 | awk '{ print "/dev/"$2 }')
grub-pc grub-pc/install_devices_empty boolean false
grub-pc grub-pc/mixed_legacy_and_grub2 boolean true
EOF

# install proxmox default kernel
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install proxmox-default-kernel

# install the main proxmox packages
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install proxmox-ve postfix open-iscsi chrony isc-dhcp-client

# install automation packages
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install packer cloud-image-utils xorriso ovmf ansible

# apply the new settings to grub
update-grub

# enable overcommit of vm memory
sysctl -w vm.overcommit_memory=1
tee /etc/sysctl.d/90-overcommit-memory.conf <<EOF
vm.overcommit_memory=1
EOF

# disable enterprise repository
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
  sed -i 's/^/# /g' /etc/apt/sources.list.d/pve-enterprise.list
fi
if [ -f /etc/apt/sources.list.d/pve-enterprise.sources ]; then
  sed -i 's/\(Components:.*pve-enterprise.*\)/\1\nEnabled: false/' /etc/apt/sources.list.d/pve-enterprise.sources
fi

# do not wait for online interfaces
systemctl mask systemd-networkd-wait-online
systemctl mask NetworkManager-wait-online

# enable proxmox mDNS advertising
tee /etc/systemd/dnssd/proxmox.dnssd <<EOF
[Service]
Name=%H
Type=_proxmox._tcp
Port=8006
EOF

# open up the port for the proxmox webinterface
ufw disable
ufw allow log 8006/tcp comment 'allow proxmox web interface'
ufw allow 5900:5999/tcp comment 'allow proxmox vnc web console'
ufw allow 3128/tcp comment 'allow proxmox spice proxy'
ufw allow 111/udp comment 'allow proxmox rpcbind'
ufw allow 5405:5412/udp comment 'allow proxmox corosync cluster traffic'
ufw allow 60000:60050/tcp comment 'allow proxmox live migration'
ufw allow 6789/tcp comment 'allow ceph monitor'
ufw allow 3300/tcp comment 'allow ceph monitor'
ufw allow 6800:7300/tcp comment 'allow ceph osd'
ufw allow 873/tcp comment 'allow ceph rsync'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
