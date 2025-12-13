#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed archiso

mkdir -p /var/tmp/archlive/{work,output} /srv/liveiso
cp -r /usr/share/archiso/configs/baseline/ /var/tmp/archlive/

# switch from erofs to squashfs as it's compression is way better
sed -i 's/airootfs_image_type=.*/airootfs_image_type="squashfs"/' /var/tmp/archlive/baseline/profiledef.sh
sed -i "s/airootfs_image_tool_options=.*/airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')/" /var/tmp/archlive/baseline/profiledef.sh

# take syslinux config from releng to enable pxe boot
rm /var/tmp/archlive/baseline/syslinux/*
cp /usr/share/archiso/configs/releng/syslinux/* /var/tmp/archlive/baseline/syslinux/

# baseline extended with build tools needed on archiso
tee -a /var/tmp/archlive/baseline/packages.x86_64 <<EOF
arch-install-scripts
bcachefs-tools
btrfs-progs
dosfstools
e2fsprogs
efibootmgr
elinks
exfatprogs
f2fs-tools
gpart
gptfdisk
grub
jfsutils
jq
kexec-tools
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
tmux
udftools
vim
wget
yq
xfsprogs
EOF
sort -u -o /var/tmp/archlive/baseline/packages.x86_64 /var/tmp/archlive/baseline/packages.x86_64

# merging releng hooks into baseline mkinitcpio to enable pxe boot
tee /var/tmp/archlive/baseline/airootfs/etc/mkinitcpio.conf.d/archiso.conf <<EOF
HOOKS=(base udev microcode modconf archiso archiso_loop_mnt archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs block filesystems)
EOF

# fingerprint
tee -a /var/tmp/archlive/baseline/airootfs/devops-linux <<EOF
$(date +%F)
EOF

# modify cloud config to use iso mount as nocloud datasource (ventoy boot bugfix)
mkdir -p /var/tmp/archlive/baseline/airootfs/etc/systemd/system/cloud-init.target.wants
tee -a /var/tmp/archlive/baseline/airootfs/etc/systemd/system/cidata.mount <<EOF
[Unit]
Description=CIDATA datasource (/cidata)
Before=cloud-init.service

[Mount]
What=/dev/disk/by-label/CIDATA
Where=/cidata
Options=X-mount.mkdir

[Install]
WantedBy=cloud-init.target
EOF
ln -s /etc/systemd/system/cidata.mount /var/tmp/archlive/baseline/airootfs/etc/systemd/system/cloud-init.target.wants/cidata.mount
mkdir -p /var/tmp/archlive/baseline/airootfs/etc/cloud/cloud.cfg.d
tee -a /var/tmp/archlive/baseline/airootfs/etc/cloud/cloud.cfg.d/10_nocloud.cfg <<EOF
datasource_list: ["NoCloud"]
datasource:
  NoCloud:
    seedfrom: file:///cidata/
EOF

# show menu entries for system information at boottime
mkdir -p /var/tmp/archlive/baseline/grub
tee -a /var/tmp/archlive/baseline/grub/grub.cfg /var/tmp/archlive/baseline/grub/loopback.cfg <<'EOF'

insmod echo
insmod read
insmod smbios
set smbios_str=""

smbios --type 0 --get-string 0x04 --set smbios_bios_vendor
smbios --type 0 --get-string 0x05 --set smbios_bios_version
smbios --type 0 --get-string 0x08 --set smbios_bios_release
set smbios_str="${smbios_str}=== BIOS Information ===\n"
set smbios_str="${smbios_str}Vendor: ${smbios_bios_vendor}\n"
set smbios_str="${smbios_str}Version: ${smbios_bios_version}\n"
set smbios_str="${smbios_str}Release: ${smbios_bios_release}\n"

smbios --type 1 --get-string 0x04 --set smbios_system_vendor
smbios --type 1 --get-string 0x05 --set smbios_system_product
smbios --type 1 --get-string 0x06 --set smbios_system_version
smbios --type 1 --get-string 0x07 --set smbios_system_serial
smbios --type 1 --get-string 0x19 --set smbios_system_sku
set smbios_str="${smbios_str}=== System Information ===\n"
set smbios_str="${smbios_str}Vendor: ${smbios_system_vendor}\n"
set smbios_str="${smbios_str}Product: ${smbios_system_product}\n"
set smbios_str="${smbios_str}Version: ${smbios_system_version}\n"
set smbios_str="${smbios_str}Serial: ${smbios_system_serial}\n"
set smbios_str="${smbios_str}SKU: ${smbios_system_sku}\n"

smbios --type 3 --get-string 0x04 --set smbios_chassis_vendor
smbios --type 3 --get-string 0x06 --set smbios_chassis_version
smbios --type 3 --get-string 0x07 --set smbios_chassis_serial
smbios --type 3 --get-string 0x08 --set smbios_chassis_asset
set smbios_str="${smbios_str}=== Chassis Information ===\n"
set smbios_str="${smbios_str}Vendor: ${smbios_chassis_vendor}\n"
set smbios_str="${smbios_str}Version: ${smbios_chassis_version}\n"
set smbios_str="${smbios_str}Serial: ${smbios_chassis_serial}\n"
set smbios_str="${smbios_str}Asset Tag: ${smbios_chassis_asset}\n"

smbios --type 4 --get-string 0x07 --set smbios_cpu_vendor
smbios --type 4 --get-string 0x10 --set smbios_cpu_version
smbios --type 4 --get-string 0x20 --set smbios_cpu_serial
smbios --type 4 --get-string 0x21 --set smbios_cpu_asset
set smbios_str="${smbios_str}=== CPU Information ===\n"
set smbios_str="${smbios_str}Vendor: ${smbios_cpu_vendor}\n"
set smbios_str="${smbios_str}Version: ${smbios_cpu_version}\n"
set smbios_str="${smbios_str}Serial: ${smbios_cpu_serial}\n"
set smbios_str="${smbios_str}Asset Tag: ${smbios_cpu_asset}\n"

menuentry "[i] System Information" --hotkey=i {
    echo -e -n "$smbios_str"
    echo "Press any key to return..."
    read
}
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
