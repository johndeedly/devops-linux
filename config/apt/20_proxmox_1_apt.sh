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
  curl -fsSL "https://download.proxmox.com/debian/proxmox-release-${VERSION_CODENAME}.gpg" | gpg --dearmor -o "/etc/apt/trusted.gpg.d/proxmox-release-${VERSION_CODENAME}.gpg"
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

# == enable iommu for gpu sharing ==
# in proxmox, after assigning the "raw gpu device" you need to select the
# "All Functions", "ROM-Bar" and "PCI-Express" options in the "Advance" tab
# https://passthroughpo.st/explaining-csm-efifboff-setting-boot-gpu-manually/
# http://vfio.blogspot.com/2014/08/vfiovga-faq.html
GRUB_CFGS=( /etc/default/grub /etc/default/grub.d/* )
for cfg in "${GRUB_CFGS[@]}"; do
  sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=.*\)"/\1 intel_iommu=on amd_iommu=on pcie_acs_override=downstream,multifunction nofb nomodeset video=vesafb:off,efifb:off"/' "$cfg" || true
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
