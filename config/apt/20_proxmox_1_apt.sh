#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    ( ( sleep 1 && rm -- "${0}" ) & )
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# add the proxmox repository and some bookworm related stuff to the package sources
tee -a /etc/apt/sources.list <<EOF

deb http://ftp.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://ftp.debian.org/debian bookworm-updates main contrib non-free non-free-firmware

deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription

deb http://security.debian.org/debian-security bookworm-security main contrib
EOF

# verify and install the proxmox repository key
echo ":: download proxmox repository certificate"
wget https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg
CHECKSUM=$(sha512sum /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg | cut -d ' ' -f1)
TARGET="7da6fe34168adc6e479327ba517796d4702fa2f8b4f0a9833f5ea6e6b48f6507a6da403a274fe201595edc86a84463d50383d07f64bdde2e3658108db7d6dc87"
if [ "$TARGET" != "$CHECKSUM" ]; then
    echo "!! checksum mismatch"
    exit 1
fi

# update and upgrade
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt update
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt upgrade --with-new-pkgs

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install ifupdown2 firewalld
systemctl stop networking || true
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install --reinstall ifupdown2
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata dpkg --configure -a

# https://www.tecmint.com/install-proxmox/
# as of today, ifupdown2 will fix itself here in a silent and wonderous way
# might break in the future, of course, most probably
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install curl software-properties-common apt-transport-https ca-certificates gnupg2

# install proxmox default kernel
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install proxmox-default-kernel

# remove all other debian kernels
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt remove linux-image-amd64 'linux-image-6.1*'

# Set hostname in etc/hosts
tee /etc/hostname <<EOF
proxmox.internal
EOF
FQDNAME=$(cat /etc/hostname)
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

# install the main proxmox packages
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install proxmox-ve postfix open-iscsi chrony packer ansible

# apply the new settings to grub
update-grub

# one bridge per interface, dhcp setup on first device
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
EOF
done

# do not wait for online interfaces
systemctl mask systemd-networkd-wait-online
systemctl mask NetworkManager-wait-online

# open up the port for the proxmox webinterface
firewall-offline-cmd --zone=public --add-port=8006/tcp

# removes the nagging "subscription missing" popup on login (no permanent solution)
sed -Ezi 's/(function\(orig_cmd\) \{)/\1\n\torig_cmd\(\);\n\treturn;/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

# sync everything to disk
sync

# cleanup
rm -- "${0}"
