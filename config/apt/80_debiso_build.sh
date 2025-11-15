#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    [ -f "${0}" ] && rm -- "${0}"
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# build tools
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install debootstrap squashfs-tools xorriso \
  isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin grub-efi-ia32-bin mtools dosfstools

# create folder structure
mkdir -p /var/tmp/deblive/{staging/{EFI/BOOT,boot/grub/x86_64-efi,isolinux,live},tmp} /srv/liveiso

# bootstrap the chroot environment
pushd /var/tmp/deblive
  (
    source /etc/os-release
    eatmydata debootstrap --arch=amd64 --include=eatmydata --variant=minbase "${VERSION_CODENAME}" /var/tmp/deblive/chroot https://deb.debian.org/debian/
    echo "${VERSION_CODENAME}-live" | tee /var/tmp/deblive/chroot/etc/hostname
  )
popd

# configure the squashfs environment
chroot /var/tmp/deblive/chroot <<EOF
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt-get -y update
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt-get -y install --no-install-recommends \
  linux-image-amd64 live-boot systemd-sysv
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt-get -y install --no-install-recommends \
  locales-all systemd-resolved cloud-init eatmydata openssh-server pv qemu-guest-agent syslinux \
  bcache-tools btrfs-progs dosfstools e2fsprogs efibootmgr exfatprogs f2fs-tools gpart gdisk \
  jfsutils jq libguestfs-tools xorriso lvm2 mtools nano nbd-client nfs-common nilfs-tools open-iscsi \
  open-vm-tools partclone parted partimage qemu-system-common qemu-user rsync fonts-terminus udftools \
  vim wget yq xfsprogs
systemctl disable network-manager
systemctl enable systemd-networkd
systemctl enable systemd-resolved
EOF

# all ethernet devices perform a DHCP lookup
tee /var/tmp/deblive/chroot/etc/systemd/network/05-wired.network <<EOF
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
EOF

# do not wait too long for network to start
mkdir -p /var/tmp/deblive/chroot/etc/systemd/system/systemd-networkd-wait-online.service.d
tee /var/tmp/deblive/chroot/etc/systemd/system/systemd-networkd-wait-online.service.d/wait-online-any.conf <<EOF
[Service]
ExecStart=
ExecStart=-/usr/lib/systemd/systemd-networkd-wait-online --operational-state=routable --any --timeout=10
EOF

# do not wait too long for network to start
mkdir -p /var/tmp/deblive/chroot/etc/systemd/system/NetworkManager-wait-online.service.d
tee /var/tmp/deblive/chroot/etc/systemd/system/NetworkManager-wait-online.service.d/wait-online-any.conf <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/nm-online -x -q -t 10
EOF

# fingerprint
tee -a /var/tmp/deblive/{chroot,staging}/devops-linux <<EOF
$(date +%F)
EOF

# create the compressed squash filesystem
mksquashfs /var/tmp/deblive/chroot /var/tmp/deblive/staging/live/filesystem.squashfs \
  -comp zstd -Xcompression-level 4 -b 1M -progress -wildcards -e boot

# copy over kernel and initrd
cp /var/tmp/deblive/chroot/boot/vmlinuz-* /var/tmp/deblive/staging/live/vmlinuz
cp /var/tmp/deblive/chroot/boot/initrd.img-* /var/tmp/deblive/staging/live/initrd

# boot menu for legacy boot
tee /var/tmp/deblive/staging/isolinux/isolinux.cfg <<'EOF'
UI vesamenu.c32

MENU TITLE Boot Menu
DEFAULT linux
TIMEOUT 150
MENU RESOLUTION 640 480
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

LABEL linux
  MENU LABEL Debian Live [BIOS/ISOLINUX]
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live
EOF

# boot menu for uefi boot
tee /var/tmp/deblive/staging/boot/grub/grub.cfg /var/tmp/deblive/staging/EFI/BOOT/grub.cfg <<'EOF'
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660

insmod all_video
insmod font

set default="0"
set timeout=15

insmod smbios
smbios --type 1 --get-string 0x04 --set smbios_system_vendor
set is_vm=false
if [ "$smbios_system_vendor" = "QEMU" ] || [ "$smbios_system_vendor" = "SeaBIOS" ]; then
    set is_vm=true
fi
if [ "$smbios_system_vendor" = "innotek GmbH" ] || [ "$smbios_system_vendor" = "Oracle Corporation" ]; then
    set is_vm=true
fi

menuentry "Debian Live [EFI/GRUB]" {
    search --no-floppy --set=root --file /devops-linux
    linux ($root)/live/vmlinuz boot=live
    initrd ($root)/live/initrd
}

submenu "Hardware Info" {
    ### SMBIOS Type 0 – BIOS Information
    menuentry "SMBIOS Type 0: BIOS Info" {
        insmod smbios
        insmod echo
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
            insmod smbios
            insmod echo
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
            insmod smbios
            insmod echo
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
            insmod smbios
            insmod echo
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
            insmod smbios
            insmod echo
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
            insmod smbios
            insmod echo
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

tee /var/tmp/deblive/tmp/grub-embed.cfg <<'EOF'
if ! [ -d "$cmdpath" ]; then
    # On some firmware, GRUB has a wrong cmdpath when booted from an optical disc.
    # https://gitlab.archlinux.org/archlinux/archiso/-/issues/183
    if regexp --set=1:isodevice '^(\([^)]+\))\/?[Ee][Ff][Ii]\/[Bb][Oo][Oo][Tt]\/?$' "$cmdpath"; then
        cmdpath="${isodevice}/EFI/BOOT"
    fi
fi
configfile "${cmdpath}/grub.cfg"
EOF

# boot firmware
cp /usr/lib/ISOLINUX/isolinux.bin /var/tmp/deblive/staging/isolinux/
cp /usr/lib/syslinux/modules/bios/* /var/tmp/deblive/staging/isolinux/
cp -r /usr/lib/grub/x86_64-efi/* /var/tmp/deblive/staging/boot/grub/x86_64-efi/

# build grub for legacy and uefi
grub-mkstandalone -O i386-efi \
  --modules="part_gpt part_msdos fat iso9660" \
  --locales="" \
  --themes="" \
  --fonts="" \
  --output="/var/tmp/deblive/staging/EFI/BOOT/BOOTIA32.EFI" \
  "boot/grub/grub.cfg=/var/tmp/deblive/tmp/grub-embed.cfg"
grub-mkstandalone -O x86_64-efi \
  --modules="part_gpt part_msdos fat iso9660" \
  --locales="" \
  --themes="" \
  --fonts="" \
  --output="/var/tmp/deblive/staging/EFI/BOOT/BOOTx64.EFI" \
  "boot/grub/grub.cfg=/var/tmp/deblive/tmp/grub-embed.cfg"

# fat16 partition for the boot process
pushd /var/tmp/deblive/staging
  dd if=/dev/zero of=efiboot.img bs=1M count=20
  mkfs.vfat efiboot.img
  mmd -i efiboot.img ::/EFI ::/EFI/BOOT
  mcopy -vi efiboot.img \
    /var/tmp/deblive/staging/EFI/BOOT/BOOTIA32.EFI \
    /var/tmp/deblive/staging/EFI/BOOT/BOOTx64.EFI \
    /var/tmp/deblive/staging/boot/grub/grub.cfg \
    ::/EFI/BOOT/
popd

# pack together the iso
xorriso \
  -as mkisofs \
  -iso-level 3 \
  -o /srv/liveiso/debian-x86_64.iso \
  -full-iso9660-filenames \
  -volid DEBLIVE \
  --mbr-force-bootable -partition_offset 16 \
  -joliet -joliet-long -rational-rock \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -eltorito-boot \
    isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --eltorito-catalog isolinux/isolinux.cat \
  -eltorito-alt-boot \
    -e --interval:appended_partition_2:all:: \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
  -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B /var/tmp/deblive/staging/efiboot.img /var/tmp/deblive/staging

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
