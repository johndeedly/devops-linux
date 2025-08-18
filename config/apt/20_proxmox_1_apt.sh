#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    ( ( sleep 1 && rm -- "${0}" ) & )
    exit 0
fi
(
  source /etc/os-release
  if [ -n "${VERSION_CODENAME}" ] && [ "${VERSION_CODENAME}" != "bookworm" ]; then
    ( ( sleep 1 && rm -- "${0}" ) & )
    exit 0
  fi
)

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# https://www.tecmint.com/install-proxmox/
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install curl software-properties-common apt-transport-https ca-certificates gnupg2

# install the proxmox repository key
echo ":: download proxmox repository certificate"
curl -fsSL https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

# add the proxmox repository to the package sources
tee /etc/apt/sources.list.d/pve-install-repo.list <<EOF
deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription
EOF

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
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt upgrade --with-new-pkgs

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install ifupdown2
systemctl stop networking || true
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install --reinstall ifupdown2
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata dpkg --configure -a

# install proxmox default kernel
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install proxmox-default-kernel

# remove all other debian kernels
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt remove linux-image-amd64 'linux-image-6.1*'

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

# one internal bridge for everything behind a virtual router
tee -a /etc/network/interfaces <<EOF

auto vmbrlan0
iface vmbrlan0 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094
EOF

# enable overcommit of vm memory
sysctl -w vm.overcommit_memory=1
tee /etc/sysctl.d/90-overcommit-memory.conf <<EOF
vm.overcommit_memory=1
EOF

# == enable iommu for gpu sharing ==
# in proxmox, after assigning the "raw gpu device" you need to select the
# "All Functions", "ROM-Bar" and "PCI-Express" options in the "Advance" tab
GRUB_CFGS=( /etc/default/grub /etc/default/grub.d/* )
for cfg in "${GRUB_CFGS[@]}"; do
  sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=.*\)"/\1 intel_iommu=on amd_iommu=on"/' "$cfg" || true
done
grub-mkconfig -o /boot/grub/grub.cfg
grub-mkconfig -o /boot/efi/EFI/debian/grub.cfg
# prevent the host from capturing the gpu
tee /etc/modprobe.d/no-host-gpu.conf <<EOF
blacklist amdgpu
blacklist radeon
blacklist nouveau
blacklist nvidia
blacklist i915
EOF
# enable iommu modules
tee /etc/modules-load.d/vfio.conf <<EOF
vfio
vfio_iommu_type1
vfio_pci
EOF

# do not wait for online interfaces
systemctl mask systemd-networkd-wait-online
systemctl mask NetworkManager-wait-online

# open up the port for the proxmox webinterface
ufw disable
ufw allow log 8006/tcp comment 'allow proxmox web interface'
ufw allow log 5900:5999/tcp comment 'allow proxmox vnc web console'
ufw allow log 3128/tcp comment 'allow proxmox spice proxy'
ufw allow log 111/udp comment 'allow proxmox rpcbind'
ufw allow log 5405:5412/udp comment 'allow proxmox corosync cluster traffic'
ufw allow log 60000:60050/tcp comment 'allow proxmox live migration'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
rm -- "${0}"
