#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed archiso

mkdir -p /var/tmp/archlive/{work,output} /srv/liveiso
cp -r /usr/share/archiso/configs/baseline/ /var/tmp/archlive/

# baseline extended with build tools needed on archiso
tee -a /var/tmp/archlive/baseline/packages.x86_64 <<EOF
arch-install-scripts
bcachefs-tools
btrfs-progs
dosfstools
e2fsprogs
efibootmgr
exfatprogs
f2fs-tools
gpart
gptfdisk
grub
jfsutils
jq
libguestfs
libisoburn
lvm2
mkinitcpio
mkinitcpio-archiso
mkinitcpio-nfs-utils
mtools
nano
nbd
nfs-utils
nilfs-utils
open-iscsi
open-vm-tools
partclone
parted
partimage
qemu-base
rsync
systemd-resolvconf
terminus-font
udftools
vim
wget
yq
xfsprogs
EOF
sort -u -o /var/tmp/archlive/baseline/packages.x86_64 /var/tmp/archlive/baseline/packages.x86_64

# merging releng hooks into baseline archiso.conf to enable pxe boot
tee /var/tmp/archlive/baseline/airootfs/etc/mkinitcpio.conf.d/archiso.conf <<EOF
HOOKS=(base udev microcode modconf archiso archiso_loop_mnt archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs block filesystems)
EOF

# fingerprint
tee -a /var/tmp/archlive/baseline/airootfs/devops-linux <<EOF
$(date +%F)
EOF

# build archiso
pushd /var/tmp/archlive
  mkarchiso -m iso -w work -o output baseline
  find output/ -type f -name "archlinux-*.iso" -print | while read -r line; do
    mv "$line" /srv/liveiso/archlinux-x86_64.iso
    break
  done
  mkarchiso -m netboot -w work -o output baseline
  find output/ -type d -name "arch" -print | while read -r line; do
    mv "$line" /srv/liveiso/arch
    break
  done
popd

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
