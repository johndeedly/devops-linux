#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    ( ( sleep 1 && rm -- "${0}" ) & )
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install live-build

mkdir -p /var/tmp/deblive/config/{bootloaders,package-lists,hooks/live} /srv/liveiso

pushd /var/tmp/deblive
  (
    source /etc/os-release
    eatmydata lb config -d "${VERSION_CODENAME}" --debian-installer live --debian-installer-distribution "${VERSION_CODENAME}" \
      --archive-areas "main non-free-firmware" --debootstrap-options "--include=eatmydata --variant=minbase"
  )
popd

# bootloader timeout
cp -r /usr/share/live/build/bootloaders/isolinux/ /var/tmp/deblive/config/bootloaders/
tee /var/tmp/deblive/config/bootloaders/isolinux/isolinux.cfg <<EOF
include menu.cfg
default vesamenu.c32
prompt 0
timeout 150
EOF
tee /var/tmp/deblive/config/bootloaders/isolinux/menu.cfg <<EOF
menu hshift 0
menu width 82

menu title Boot menu
include stdmenu.cfg
include live.cfg

menu clear
EOF

# eat my data in chroot
tee -a /var/tmp/deblive/config/environment.chroot <<EOF
LD_PRELOAD=libeatmydata.so
EOF

# same packages as archiso setup
tee /var/tmp/deblive/config/package-lists/pkgs.list.chroot <<EOF
systemd-resolved
cloud-init
eatmydata
openssh-server
pv
qemu-guest-agent
syslinux
bcache-tools
btrfs-progs
dosfstools
e2fsprogs
efibootmgr
exfatprogs
f2fs-tools
gpart
gdisk
jfsutils
jq
libguestfs-tools
xorriso
lvm2
mtools
nano
nbd-client
nfs-common
nilfs-tools
open-iscsi
open-vm-tools
partclone
parted
partimage
qemu-system-common
qemu-user
rsync
fonts-terminus
udftools
vim
wget
yq
xfsprogs
EOF

tee /var/tmp/deblive/config/hooks/live/0025-enable-services.hook.chroot <<EOF
#!/bin/sh

echo I: Disable services
systemctl disable network-manager

echo I: Enable services
systemctl enable systemd-networkd
systemctl enable systemd-resolved

echo I: Configure services
tee /etc/systemd/network/05-wired.network <<EOX
[Match]
Name=en* eth*
Type=ether

[Network]
DHCP=yes
MulticastDNS=yes

[DHCPv4]
RouteMetric=10

[IPv6AcceptRA]
RouteMetric=10

[DHCPPrefixDelegation]
RouteMetric=10

[IPv6Prefix]
RouteMetric=10
EOX

mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
tee /etc/systemd/system/systemd-networkd-wait-online.service.d/wait-online-any.conf <<EOX
[Service]
ExecStart=
ExecStart=-/usr/lib/systemd/systemd-networkd-wait-online --operational-state=routable --any --timeout=10
EOX

mkdir -p /etc/systemd/system/NetworkManager-wait-online.service.d
tee /etc/systemd/system/NetworkManager-wait-online.service.d/wait-online-any.conf <<EOX
[Service]
ExecStart=
ExecStart=-/usr/bin/nm-online -x -q -t 10
EOX
EOF
chmod +x /var/tmp/deblive/config/hooks/live/0025-enable-services.hook.chroot

# build the iso
pushd /var/tmp/deblive
  eatmydata lb build
  find ./ -type f -name "live-image-*.iso" -print | while read -r line; do
    mv "$line" /srv/liveiso/debian-x86_64.iso
    break
  done
popd

# sync everything to disk
sync

# cleanup
rm -- "${0}"
