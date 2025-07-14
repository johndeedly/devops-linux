#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# check end of life
ENDOFLIFEURL=$(yq -r '.setup as $setup | .endoflife[$setup.distro]' /var/lib/cloud/instance/config/setup.yml)
if [ -z "$ENDOFLIFEURL" ] || [[ "$ENDOFLIFEURL" =~ [nN][uU][lL][lL] ]]; then
    echo ":: rolling release distro"
else
    ENDOFLIFEFILE="$(mktemp)"
    wget -c -O "${ENDOFLIFEFILE}" --progress=dot "${ENDOFLIFEURL}"
    eoldate=$(jq -r '.eol' "${ENDOFLIFEFILE}")
    epoch=$(date -d "$eoldate" +%s)
    rm "$ENDOFLIFEFILE"
    if [ "$epoch" -lt "$(date -d '1 day ago' +%s)" ] ; then
        echo "!! end of life reached. No security updates will be available any more: $eoldate"
        exit 1
    else
        echo ":: end of life not reached yet: $eoldate"
    fi
fi

# prepare setup variables
CLOUD_IMAGE_PATH="/iso/$(yq -r '.setup as $setup | .images[$setup.distro]' /var/lib/cloud/instance/config/setup.yml)"
if [ -z "$CLOUD_IMAGE_PATH" ]; then
    echo "!! missing cloud image entry"
    exit 1
fi
TARGET_DEVICE=$(yq -r '.setup.target' /var/lib/cloud/instance/config/setup.yml)
if [ "$TARGET_DEVICE" == "auto" ] || [ -z "$TARGET_DEVICE" ]; then
    if [ -e /dev/vda ]; then
        TARGET_DEVICE="/dev/vda"
    elif [ -e /dev/nvme0n1 ]; then
        TARGET_DEVICE="/dev/nvme0n1"
    elif [ -e /dev/sda ]; then
        TARGET_DEVICE="/dev/sda"
    else
        echo "!! no target device found"
        exit 1
    fi
    if ! cmp <(dd "if=$TARGET_DEVICE" bs=1M count=16 2>/dev/null) <(dd if=/dev/zero bs=1M count=16 2>/dev/null) >/dev/null; then
        echo "!! the target device $TARGET_DEVICE is not empty"
        echo "!! force installation via \".setup.target\" in setup.yml"
        exit 1
    fi
fi
# download image to temp dir when not provisioned via iso
if ! [ -f "${CLOUD_IMAGE_PATH}" ]; then
    DOWNLOAD_IMAGE_PATH="$(yq -r '.setup as $setup | .download[$setup.distro]' /var/lib/cloud/instance/config/setup.yml)"
    if [ -z "$DOWNLOAD_IMAGE_PATH" ]; then
        echo "!! image download is required, but no url entry was found in config"
        exit 1
    fi
    CLOUD_IMAGE_PATH="$(mktemp -d)/$(yq -r '.setup as $setup | .images[$setup.distro]' /var/lib/cloud/instance/config/setup.yml)"
    wget -c -O "${CLOUD_IMAGE_PATH}" --progress=dot:giga "${DOWNLOAD_IMAGE_PATH}"
fi
echo "CLOUD-IMAGE: ${CLOUD_IMAGE_PATH}, TARGET: ${TARGET_DEVICE}"

if file "${CLOUD_IMAGE_PATH}" | grep -q QCOW; then
    qemu-img convert -O raw "${CLOUD_IMAGE_PATH}" "${TARGET_DEVICE}"
elif file "${CLOUD_IMAGE_PATH}" | grep -q "\(XZ\|gzip\) compressed"; then
    LARGEST_FILE=$(tar -tvf "${CLOUD_IMAGE_PATH}" | sort -n | grep -vE "^d" | head -1 | awk '{print $9}')
    tar -xO "${LARGEST_FILE}" -f "${CLOUD_IMAGE_PATH}" | \
        dd "of=${TARGET_DEVICE}" bs=1M iflag=fullblock status=progress
else
    echo "!! wrong image file"
    exit 1
fi

# update partitions in kernel
partx -u "${TARGET_DEVICE}"
sleep 1

# resize main ext4/btrfs partition
ROOT_PART=( $(lsblk -no PATH,PARTN,FSTYPE,PARTTYPENAME "${TARGET_DEVICE}" | sed -e '/root\|linux filesystem/I!d' | head -n1) )
echo "ROOT: ${TARGET_DEVICE}, partition ${ROOT_PART[1]}"
ENCRYPT_ENABLED="$(yq -r '.setup.encrypt.enabled' /var/lib/cloud/instance/config/setup.yml)"
ENCRYPT_PASSWD="$(yq -r '.setup.encrypt.password' /var/lib/cloud/instance/config/setup.yml)"
ENCRYPT_IMAGE="$(yq -r '.setup.encrypt.image' /var/lib/cloud/instance/config/setup.yml)"
if [ -n "$ENCRYPT_ENABLED" ] && [[ "$ENCRYPT_ENABLED" =~ [Yy][Ee][Ss] ]]; then
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    name "${ROOT_PART[1]}" root \
    resizepart "${ROOT_PART[1]}" 16GiB \
    mkpart nextroot ext4 16GiB 100%
else
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    name "${ROOT_PART[1]}" root \
    resizepart "${ROOT_PART[1]}" 100%
fi

# update partitions in kernel again
partx -u "${TARGET_DEVICE}"
sleep 1

# encrypt and open the provided system root
if [ -n "$ENCRYPT_ENABLED" ] && [[ "$ENCRYPT_ENABLED" =~ [Yy][Ee][Ss] ]]; then
  NEWROOT_PART=( $(lsblk -no PATH,PARTN,PARTLABEL "${TARGET_DEVICE}" | sed -e '/nextroot/I!d' | head -n1) )
  echo "NEWROOT: ${TARGET_DEVICE}, partition ${NEWROOT_PART[1]}"
  echo "Encrypt device ${NEWROOT_PART[0]}"
  printf "%s" "${ENCRYPT_PASSWD}" | (cryptsetup luksFormat --verbose -d - "${NEWROOT_PART[0]}")
  printf "%s" "${ENCRYPT_PASSWD}" | (cryptsetup luksOpen -d - "${NEWROOT_PART[0]}" nextroot)
  cryptsetup luksDump "${NEWROOT_PART[0]}"
fi

# resize main filesystem
if [[ "${ROOT_PART[2]}" =~ [bB][tT][rR][fF][sS] ]]; then
    echo ":: resize root btrfs"
    mount "${ROOT_PART[0]}" /mnt
    btrfs filesystem resize max /mnt
    sync
    umount -l /mnt
elif [[ "${ROOT_PART[2]}" =~ [eE][xX][tT]4 ]]; then
    echo ":: resize root ext4"
    e2fsck -y -f "${ROOT_PART[0]}"
    mount "${ROOT_PART[0]}" /mnt
    resize2fs -p "${ROOT_PART[0]}"
    sync
    umount -l /mnt
elif [[ "${ROOT_PART[2]}" =~ [xX][fF][sS] ]]; then
    echo ":: resize root xfs"
    mount "${ROOT_PART[0]}" /mnt
    xfs_growfs -d /mnt
    sync
    umount -l /mnt
fi

# create btrfs filesystem in encrypted partition
if [ -n "$ENCRYPT_ENABLED" ] && [[ "$ENCRYPT_ENABLED" =~ [Yy][Ee][Ss] ]]; then
  mkfs.btrfs -L nextroot /dev/mapper/nextroot
fi

# bootable system
DISTRO_NAME=$(yq -r '.setup.distro' /var/lib/cloud/instance/config/setup.yml)
BIOS_PART=( $(lsblk -no PARTN,PARTTYPENAME "${TARGET_DEVICE}" | sed -e '/^ *[1-9]/!d' -e '/BIOS/I!d' | head -n1) )
EFI_PART=( $(lsblk -no PARTN,PARTTYPENAME "${TARGET_DEVICE}" | sed -e '/^ *[1-9]/!d' -e '/EFI/I!d' | head -n1) )
echo "BIOS: ${TARGET_DEVICE}, partition ${BIOS_PART[0]}"
echo "EFI: ${TARGET_DEVICE}, partition ${EFI_PART[0]}"
if [ -n "${BIOS_PART[0]}" ] && [ -n "${EFI_PART[0]}" ]; then
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    name "${BIOS_PART[0]}" bios \
    name "${EFI_PART[0]}" efi
elif [ -n "${EFI_PART[0]}" ]; then
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    name "${EFI_PART[0]}" efi
elif [ -n "${BIOS_PART[0]}" ]; then
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    name "${BIOS_PART[0]}" bios
else
  echo "!! neither efi nor boot partitions found"
  exit 1
fi
# remove duplicate efi entries
efibootmgr | sed -e '/'"${DISTRO_NAME}"'/I!d' | while read -r bootentry; do
    bootnum=$(echo "$bootentry" | grep -Po "[A-F0-9]{4}" | head -n1)
    if [ -n "$bootnum" ]; then
        printf ":: remove existing ${DISTRO_NAME} entry %s\n" "$bootnum"
        efibootmgr -b "$bootnum" -B
    fi
done
# create new entry
efibootmgr -c -d "${TARGET_DEVICE}" -p "${EFI_PART[0]}" -L "${DISTRO_NAME}" -l /EFI/BOOT/BOOTX64.EFI || true

# mount detected root filesystem
mount "${ROOT_PART[0]}" /mnt

# prefill package cache
if [ -f /mnt/bin/apt ]; then
    if [ -d /iso/stage/apt ]; then
        mkdir -p /mnt/var/cache/apt
        rsync -av /iso/stage/apt/ /mnt/var/cache/apt/
    fi
elif [ -f /mnt/bin/pacman ]; then
    if [ -d /iso/stage/pacman ]; then
        mkdir -p /mnt/var/cache/pacman
        rsync -av /iso/stage/pacman/ /mnt/var/cache/pacman/
    fi
elif [ -f /mnt/bin/yum ]; then
    if [ -d /iso/stage/yum ]; then
        mkdir -p /mnt/var/cache/yum
        rsync -av /iso/stage/yum/ /mnt/var/cache/yum/
    fi
fi

# create a 2GiB swap file
# https://btrfs.readthedocs.io/en/latest/Swapfile.html
if [ -d /mnt/swap ]; then
  rm -r /mnt/swap
fi
install -d -m 0700 -o root -g root /mnt/swap
truncate -s 0 /mnt/swap/swapfile
chattr +C /mnt/swap/swapfile || true
fallocate -l 2G /mnt/swap/swapfile
chmod 0600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile
if ! grep -q '/swap/swapfile' /mnt/etc/fstab; then
  tee -a /mnt/etc/fstab <<EOF
/swap/swapfile none swap defaults 0 0
EOF
fi

# write the stage user-data to the cidata directory on disk
install -d -m 0700 -o root -g root /mnt/cidata
cp /var/lib/cloud/instance/provision/meta-data /var/lib/cloud/instance/provision/user-data /mnt/cidata/
chmod 0600 /mnt/cidata/{meta,user}-data
tee -a /mnt/etc/cloud/cloud.cfg <<EOF

datasource_list: ["NoCloud"]
datasource:
  NoCloud:
    seedfrom: file:///cidata/
EOF

# set local package mirror
PKG_MIRROR=$(yq -r '.setup.pkg_mirror' /var/lib/cloud/instance/config/setup.yml)
if [ -n "$PKG_MIRROR" ] && [ "false" != "$PKG_MIRROR" ]; then
    if [ -f /mnt/bin/apt ] && grep -q "Debian" /mnt/etc/os-release; then
        tee /mnt/etc/apt/sources.list.d/debian.sources <<EOF
# auto configured through setup.yml
# <example>
#   Types: deb
#   URIs: http://mirror.internal:8080/debian
#   Suites: bookworm bookworm-updates bookworm-backports bookworm-security
#   Components: main contrib non-free non-free-firmware
#   Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
# </example>

${PKG_MIRROR}
EOF
    elif [ -f /mnt/bin/apt ] && grep -q "Ubuntu" /mnt/etc/os-release; then
        tee /mnt/etc/apt/sources.list.d/ubuntu.sources <<EOF
# auto configured through setup.yml
# <example>
#   Types: deb
#   URIs: http://mirror.internal:8080/ubuntu
#   Suites: noble noble-updates noble-backports noble-security
#   Components: main universe restricted multiverse
#   Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
# </example>

${PKG_MIRROR}
EOF
    elif [ -f /mnt/bin/pacman ]; then
        tee /mnt/etc/pacman.d/mirrorlist <<EOF
# auto configured through setup.yml
# <example>
#   Server = http://mirror.internal:8080/archlinux/\$repo/os/\$arch
# </example>

${PKG_MIRROR}
EOF
    elif [ -f /mnt/bin/yum ]; then
        tee /mnt/etc/yum.repos.d/rocky.repo <<EOF
# auto configured through setup.yml
# <example>
#   [baseos]
#   name=Rocky Linux \$releasever - BaseOS
#   baseurl=http://mirror.internal:8080/rocky/\$contentdir/\$releasever/BaseOS/\$basearch/os/
#   gpgcheck=1
#   enabled=1
#   countme=1
#   metadata_expire=6h
#   gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9
#
#   [appstream]
#   name=Rocky Linux \$releasever - AppStream
#   baseurl=http://mirror.internal:8080/rocky/\$contentdir/\$releasever/AppStream/\$basearch/os/
#   gpgcheck=1
#   enabled=1
#   countme=1
#   metadata_expire=6h
#   gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9
#
#   [crb]
#   name=Rocky Linux \$releasever - CRB
#   baseurl=http://mirror.internal:8080/rocky/\$contentdir/\$releasever/CRB/\$basearch/os/
#   gpgcheck=1
#   enabled=1
#   countme=1
#   metadata_expire=6h
#   gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9
# </example>

${PKG_MIRROR}
EOF
    fi
fi

# finalize /mnt
cp /cidata_log /mnt/cidata_log || true
chmod 0600 /mnt/cidata_log || true
sync
umount -l /mnt

# mount encrypted filesystem and prefill it with the tarball under /iso/tar/*.tar.gz
if [ -n "$ENCRYPT_ENABLED" ] && [[ "$ENCRYPT_ENABLED" =~ [Yy][Ee][Ss] ]]; then
  mount /dev/mapper/nextroot /mnt
  if [ -d /iso/tar ] && [ -f "/iso/tar/${ENCRYPT_IMAGE}" ]; then
    echo ":: Extract tarball /iso/tar/${ENCRYPT_IMAGE}"
    ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -xf "/iso/tar/${ENCRYPT_IMAGE}" -C /mnt
  fi

  # finalize /mnt again
  cp /cidata_log /mnt/cidata_log || true
  chmod 0600 /mnt/cidata_log || true
  sync
  umount -l /mnt
  cryptsetup luksClose nextroot
  sync
fi

sleep 1
lsblk -o +LABEL,PARTLABEL,FSTYPE,PARTTYPENAME "${TARGET_DEVICE}"
sleep 5

# sync everything to disk
sync

# cleanup
rm -- "${0}"
