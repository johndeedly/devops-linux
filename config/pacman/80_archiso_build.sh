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
insmod test
insmod read

insmod smbios
smbios --type 1 --get-string 0x04 --set smbios_system_vendor
set is_vm=false
if [ "$smbios_system_vendor" = "QEMU" ] || [ "$smbios_system_vendor" = "SeaBIOS" ]; then
    set is_vm=true
fi
if [ "$smbios_system_vendor" = "innotek GmbH" ] || [ "$smbios_system_vendor" = "Oracle Corporation" ]; then
    set is_vm=true
fi

submenu "Hardware Info" {
    ### SMBIOS Type 0 – BIOS Information
    menuentry "SMBIOS Type 0: BIOS Info" {
        echo "=== SMBIOS Type 0: BIOS Information ==="
        echo -n "Vendor: "
        smbios --type 0 --get-string 0x04
        echo -n "BIOS Version: "
        smbios --type 0 --get-string 0x05
        echo -n "BIOS Release Date: "
        smbios --type 0 --get-string 0x08
        echo "=== End of SMBIOS Type 0 ==="
        echo "Press any key to return..."
        read
    }
    
    if [ "$is_vm" = "false" ]; then
        ### SMBIOS Type 1 – System Information
        menuentry "SMBIOS Type 1: System Info" {
            echo "=== SMBIOS Type 1: System Information ==="
            echo -n "Manufacturer: "
            smbios --type 1 --get-string 0x04
            echo -n "Product Name: "
            smbios --type 1 --get-string 0x05
            echo -n "Version: "
            smbios --type 1 --get-string 0x06
            echo -n "Serial Number: "
            smbios --type 1 --get-string 0x07
            echo -n "UUID: "
            smbios --type 1 --get-string 0x08
            echo -n "SKU Number: "
            smbios --type 1 --get-string 0x19
            echo -n "Family: "
            smbios --type 1 --get-string 0x1A
            echo "=== End of SMBIOS Type 1 ==="
            echo "Press any key to return..."
            read
        }
        
        ### SMBIOS Type 2 – Baseboard
        menuentry "SMBIOS Type 2: Baseboard Info" {
            echo "=== SMBIOS Type 2: Baseboard Information ==="
            echo -n "Manufacturer: "
            smbios --type 2 --get-string 0x04
            echo -n "Product Name: "
            smbios --type 2 --get-string 0x05
            echo -n "Version: "
            smbios --type 2 --get-string 0x06
            echo -n "Serial Number: "
            smbios --type 2 --get-string 0x07
            echo -n "Asset Tag: "
            smbios --type 2 --get-string 0x08
            echo -n "Location in Chassis: "
            smbios --type 2 --get-string 0x0A
            echo "=== End of SMBIOS Type 2 ==="
            echo "Press any key to return..."
            read
        }
        
        ### SMBIOS Type 3 – Chassis
        menuentry "SMBIOS Type 3: Chassis Info" {
            echo "=== SMBIOS Type 3: Chassis Information ==="
            echo -n "Manufacturer: "
            smbios --type 3 --get-string 0x04
            echo -n "Version: "
            smbios --type 3 --get-string 0x06
            echo -n "Serial Number: "
            smbios --type 3 --get-string 0x07
            echo -n "Asset Tag: "
            smbios --type 3 --get-string 0x08
            echo "=== End of SMBIOS Type 3 ==="
            echo "Press any key to return..."
            read
        }
        
        ### SMBIOS Type 4 – Processor
        menuentry "SMBIOS Type 4: Processor Info" {
            echo "=== SMBIOS Type 4: Processor Information ==="
            echo -n "Socket Designation: "
            smbios --type 4 --get-string 0x04
            echo -n "Processor Manufacturer: "
            smbios --type 4 --get-string 0x07
            echo -n "Processor Version: "
            smbios --type 4 --get-string 0x10
            echo -n "Serial Number: "
            smbios --type 4 --get-string 0x20
            echo -n "Asset Tag: "
            smbios --type 4 --get-string 0x21
            echo -n "Part Number: "
            smbios --type 4 --get-string 0x22
            echo "=== End of SMBIOS Type 4 ==="
            echo "Press any key to return..."
            read
        }
        
        ### SMBIOS Type 17 – Memory Device
        menuentry "SMBIOS Type 17: Memory Device Info" {
            echo "=== SMBIOS Type 17: Memory Device Information ==="
            echo -n "Device Locator: "
            smbios --type 17 --get-string 0x10
            echo -n "Bank Locator: "
            smbios --type 17 --get-string 0x11
            echo -n "Manufacturer: "
            smbios --type 17 --get-string 0x17
            echo -n "Serial Number: "
            smbios --type 17 --get-string 0x18
            echo -n "Asset Tag: "
            smbios --type 17 --get-string 0x19
            echo -n "Part Number: "
            smbios --type 17 --get-string 0x1A
            echo "=== End of SMBIOS Type 17 ==="
            echo "Press any key to return..."
            read
        }
    fi
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
