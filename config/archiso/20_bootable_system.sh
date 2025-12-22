#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# prepare setup variables
DISTRO_NAME=$(yq -r '.setup.distro' /var/lib/cloud/instance/config/setup.yml)
TARGET_DEVICE=$(yq -r '.setup.target' /var/lib/cloud/instance/config/setup.yml)
if [ "$TARGET_DEVICE" == "select" ]; then
    ip=$(ip addr show $(ip route show default | awk '/default via/ {print $5}') | \
        awk '/inet / {print $2}' | cut -d/ -f1 | grep -vE '^127\.|^169\.254\.' | head -n1)
    ip6=$(ip -6 addr show $(ip -6 route show default | awk '/default via/ {print $5}') | \
        awk '/inet6 / {print $2}' | cut -d/ -f1 | grep -vE '^fe80|^::1' | head -n1)
    port=5000
    echo "Open a webbrowser and point it to:"
    [ -n "$ip" ] && echo "-> http://$ip:$port/"
    [ -n "$ip6" ] && echo "-> http://[$ip6]:$port/"
    TARGET_DEVICE=$( python3 - <<EOF
import http.server
import socketserver
import subprocess
import threading
from urllib.parse import parse_qs

selected = None

result = subprocess.run(
    ["lsblk", "-dn", "-o", "PATH,SIZE,TYPE"],
    stdout=subprocess.PIPE,
    text=True
)
disks = []
for line in result.stdout.splitlines():
    path, size, typename = line.split()
    if typename == "disk":
        disks.append((path, size))

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()
            html = "<h2>Choose installation target</h2><form method='POST'>"
            for path, size in disks:
                html += f"<input type='radio' name='disk' value='{path}'> {path} ({size})<br>"
            html += "<input type='submit' value='Send'></form>"
            self.wfile.write(html.encode())
        else:
            self.send_error(404)

    def do_POST(self):
        global selected
        length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(length).decode()
        data = parse_qs(post_data)
        selected = data.get("disk", [""])[0]
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        for path, size in disks:
            if selected == path:
                self.wfile.write(f"<h2>Use installation disk: {selected}</h2>".encode())
                threading.Thread(target=httpd.shutdown, daemon=True).start()
                return
        selected = None

with socketserver.TCPServer(("", $port), Handler) as httpd:
    while selected is None:
        httpd.handle_request()

print(selected if selected else "")
EOF
    )
    if [ -z "$TARGET_DEVICE" ] || ! [ -e "$TARGET_DEVICE" ]; then
        echo "!! error selecting target"
        exit 1
    fi
elif [ "$TARGET_DEVICE" == "auto" ] || [ -z "$TARGET_DEVICE" ]; then
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
# download image to temp dir when no cached image on the iso can be found
CLOUD_IMAGE_PATH="/iso/$(yq -r '.setup as $setup | .images[$setup.distro]' /var/lib/cloud/instance/config/setup.yml)"
if ! [ -f "${CLOUD_IMAGE_PATH}" ]; then
    DOWNLOAD_IMAGE_PATH="$(yq -r '.setup as $setup | .download[$setup.distro]' /var/lib/cloud/instance/config/setup.yml)"
    if [ -z "$DOWNLOAD_IMAGE_PATH" ]; then
        echo "!! image download is required, but no url entry was found in config"
        exit 1
    fi
    CLOUD_IMAGE_PATH="$(mktemp -d)/$(yq -r '.setup as $setup | .images[$setup.distro]' /var/lib/cloud/instance/config/setup.yml)"
    wget -c -O "${CLOUD_IMAGE_PATH}" --progress=dot:giga "${DOWNLOAD_IMAGE_PATH}"
    if ! [ -f "${CLOUD_IMAGE_PATH}" ]; then
        echo "!! image download is required, but failed"
        exit 1
    fi
    # update cache with downloaded image (only if the image isn't an out-of-the-box ready image)
    if [ "xdump" != "x${DISTRO_NAME}" ]; then
        if systemd-detect-virt && mount -t 9p database.0 /mnt; then
            rsync -av "${CLOUD_IMAGE_PATH}" /mnt/
            sync
            umount /mnt
        fi
    fi
fi
echo "CLOUD-IMAGE: ${CLOUD_IMAGE_PATH}, TARGET: ${TARGET_DEVICE}"

if file "${CLOUD_IMAGE_PATH}" | grep -q QCOW; then
    qemu-img convert -O raw "${CLOUD_IMAGE_PATH}" "${TARGET_DEVICE}"
elif file "${CLOUD_IMAGE_PATH}" | grep -q "XZ compressed"; then
    xz -cd <"${CLOUD_IMAGE_PATH}" | dd "of=${TARGET_DEVICE}" bs=1M iflag=fullblock status=progress
elif file "${CLOUD_IMAGE_PATH}" | grep -q "Zstandard compressed"; then
    zstd -cd <"${CLOUD_IMAGE_PATH}" | dd "of=${TARGET_DEVICE}" bs=1M iflag=fullblock status=progress
elif file "${CLOUD_IMAGE_PATH}" | grep -q "bzip2 compressed"; then
    bzip2 -cd <"${CLOUD_IMAGE_PATH}" | dd "of=${TARGET_DEVICE}" bs=1M iflag=fullblock status=progress
elif file "${CLOUD_IMAGE_PATH}" | grep -q "LZMA compressed"; then
    lzma -cd <"${CLOUD_IMAGE_PATH}" | dd "of=${TARGET_DEVICE}" bs=1M iflag=fullblock status=progress
elif file "${CLOUD_IMAGE_PATH}" | grep -q "gzip compressed"; then
    gzip -cd <"${CLOUD_IMAGE_PATH}" | dd "of=${TARGET_DEVICE}" bs=1M iflag=fullblock status=progress
else
    echo "[FAIL] unknown image file type"
    exit 1
fi

# update partitions in kernel
partx -u "${TARGET_DEVICE}"
sleep 1

# resize main ext4/btrfs partition
ROOT_PART=( $(lsblk -no PATH,PARTN,FSTYPE,PARTTYPE "${TARGET_DEVICE}" | sed -e '/4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709/I!d' | head -n1) )
if [ -z "${ROOT_PART[1]}" ]; then
    # ubuntu/alma
    ROOT_PART=( $(lsblk -no PATH,PARTN,FSTYPE,LABEL,PARTLABEL,PARTTYPE "${TARGET_DEVICE}" | sed -e '/21686148-6449-6E6F-744E-656564454649/Id' \
        -e '/C12A7328-F81F-11D2-BA4B-00A0C93EC93B/Id' -e '/[^a-z]root/I!d' | head -n1) )
fi
echo "ROOT: ${TARGET_DEVICE}, partition ${ROOT_PART[1]}"
ENCRYPT_ENABLED="$(yq -r '.setup.encrypt.enabled' /var/lib/cloud/instance/config/setup.yml)"
ENCRYPT_SSHUSER="$(yq -r '.setup.encrypt.sshuser' /var/lib/cloud/instance/config/setup.yml)"
ENCRYPT_SSHHASH="$(yq -r '.setup.encrypt.sshhash' /var/lib/cloud/instance/config/setup.yml)"
ENCRYPT_PASSWD="$(yq -r '.setup.encrypt.password' /var/lib/cloud/instance/config/setup.yml)"
ENCRYPT_IMAGE="$(yq -r '.setup.encrypt.image' /var/lib/cloud/instance/config/setup.yml)"
if [ -n "$ENCRYPT_ENABLED" ] && [[ "$ENCRYPT_ENABLED" =~ [Yy][Ee][Ss] ]] \
    || [[ "$ENCRYPT_ENABLED" =~ [Oo][Nn] ]] || [[ "$ENCRYPT_ENABLED" =~ [Tt][Rr][Uu][Ee] ]]; then
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    type "${ROOT_PART[1]}" 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709 \
    resizepart "${ROOT_PART[1]}" 16GiB \
    mkpart nextroot ext4 16GiB 100%
else
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    type "${ROOT_PART[1]}" 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709 \
    resizepart "${ROOT_PART[1]}" 100%
fi

# update partitions in kernel again
partx -u "${TARGET_DEVICE}"
sleep 1

# encrypt and open the provided system root
if [ -n "$ENCRYPT_ENABLED" ] && [[ "$ENCRYPT_ENABLED" =~ [Yy][Ee][Ss] ]] \
    || [[ "$ENCRYPT_ENABLED" =~ [Oo][Nn] ]] || [[ "$ENCRYPT_ENABLED" =~ [Tt][Rr][Uu][Ee] ]]; then
  NEWROOT_PART=( $(lsblk -no PATH,PARTN,PARTLABEL,PARTTYPE "${TARGET_DEVICE}" | sed -e '/21686148-6449-6E6F-744E-656564454649/Id' \
      -e '/C12A7328-F81F-11D2-BA4B-00A0C93EC93B/Id' -e '/4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709/Id' \
      -e '/[^a-z]nextroot/I!d' | head -n1) )
  echo "NEWROOT: ${TARGET_DEVICE}, partition ${NEWROOT_PART[1]}"
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    type "${NEWROOT_PART[1]}" CA7D7CCB-63ED-4C53-861C-1742536059CC
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
if [ -n "$ENCRYPT_ENABLED" ] && [[ "$ENCRYPT_ENABLED" =~ [Yy][Ee][Ss] ]] \
    || [[ "$ENCRYPT_ENABLED" =~ [Oo][Nn] ]] || [[ "$ENCRYPT_ENABLED" =~ [Tt][Rr][Uu][Ee] ]]; then
  mkfs.btrfs -L nextroot /dev/mapper/nextroot
fi

# bootable system
BIOS_PART=( $(lsblk -no PARTN,PATH,PARTTYPE "${TARGET_DEVICE}" | sed -e '/21686148-6449-6E6F-744E-656564454649/I!d' | head -n1) )
EFI_PART=( $(lsblk -no PARTN,PATH,PARTTYPE "${TARGET_DEVICE}" | sed -e '/C12A7328-F81F-11D2-BA4B-00A0C93EC93B/I!d' | head -n1) )
BOOT_PART=( $(lsblk -no PARTN,PATH,PARTTYPE "${TARGET_DEVICE}" | sed -e '/BC13C2FF-59E6-4262-A352-B275FD6F7172/I!d' | head -n1) )
if [ -z "${BOOT_PART[0]}" ]; then
    # alma linux
    BOOT_PART=( $(lsblk -no PARTN,PATH,LABEL,PARTLABEL,PARTTYPE "${TARGET_DEVICE}" | sed -e '/21686148-6449-6E6F-744E-656564454649/Id' \
      -e '/C12A7328-F81F-11D2-BA4B-00A0C93EC93B/Id' -e '/4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709/Id' -e '/[^a-z]boot/I!d' | head -n1) )
fi
echo "BIOS: ${TARGET_DEVICE}, partition ${BIOS_PART[0]}"
echo "EFI: ${TARGET_DEVICE}, partition ${EFI_PART[0]}"
echo "BOOT: ${TARGET_DEVICE}, partition ${BOOT_PART[0]}"
if [ -n "${BIOS_PART[0]}" ] && [ -n "${EFI_PART[0]}" ]; then
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    type "${BIOS_PART[0]}" 21686148-6449-6E6F-744E-656564454649 \
    type "${EFI_PART[0]}" C12A7328-F81F-11D2-BA4B-00A0C93EC93B
elif [ -n "${EFI_PART[0]}" ]; then
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    type "${EFI_PART[0]}" C12A7328-F81F-11D2-BA4B-00A0C93EC93B
elif [ -n "${BIOS_PART[0]}" ]; then
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    type "${BIOS_PART[0]}" 21686148-6449-6E6F-744E-656564454649
else
  echo "!! neither efi nor bios partitions found"
  exit 1
fi
if [ -n "${BOOT_PART[0]}" ]; then
  LC_ALL=C parted -s -a optimal --fix -- "${TARGET_DEVICE}" \
    type "${BOOT_PART[0]}" BC13C2FF-59E6-4262-A352-B275FD6F7172
fi
if [ -n "${EFI_PART[0]}" ] && [ -e /sys/firmware/efi/efivars ]; then
    # mount detected efi filesystem
    mount "${EFI_PART[1]}" /mnt
    # remove duplicate efi entries
    efibootmgr | sed -e '/'"${DISTRO_NAME}"'/I!d' | while read -r bootentry; do
        bootnum=$(echo "$bootentry" | grep -Po "[A-F0-9]{4}" | head -n1)
        if [ -n "$bootnum" ]; then
            printf ":: remove existing ${DISTRO_NAME} entry %s\n" "$bootnum"
            efibootmgr -b "$bootnum" -B
        fi
    done
    # find a candidate for the fallback bootloader
    # shim is needed when secure boot is enabled, but it defaults to grub either way
    GRUBX64EFI=( $(find /mnt -iname "shimx64.efi" -printf "%P ") )
    if [ "${#GRUBX64EFI[@]}" = 0 ]; then
        # if no shim is present, grub is used next in list
        GRUBX64EFI=( $(find /mnt -iname "grubx64.efi" -printf "%P ") )
        if [ "${#GRUBX64EFI[@]}" = 0 ]; then
            # if no grub is present alltogether, the systemd bootloader could be there
            GRUBX64EFI=( $(find /mnt -iname "systemd-bootx64.efi" -printf "%P ") )
            if [ "${#GRUBX64EFI[@]}" = 0 ]; then
                # if all of the above are not there, maybe there is somewhere the default location bootloader, hopefully
                GRUBX64EFI=( $(find /mnt -iname "bootx64.efi" -printf "%P ") )
            fi
        fi
    fi
    # the grub bootloader has a config somewhere
    GRUBCFG=( $(find /mnt -iname "grub.cfg" -printf "%P ") )
    # copy next fallback bootloader
    if [ "${#GRUBX64EFI[@]}" -gt 0 ] && [ "/mnt/${GRUBX64EFI[0]}" != "/mnt/EFI/BOOT/BOOTX64.EFI" ]; then
        mkdir -p /mnt/EFI/BOOT
        echo "[ ## ] copy /mnt/${GRUBX64EFI[0]} to /mnt/EFI/BOOT/BOOTX64.EFI"
        cp "/mnt/${GRUBX64EFI[0]}" /mnt/EFI/BOOT/BOOTX64.EFI
    fi
    # copy grub config
    if [ "${#GRUBCFG[@]}" -gt 0 ]; then
        mkdir -p /mnt/EFI/BOOT
        find /mnt/EFI -maxdepth 1 -type d -printf '%p\n' | while read -r line; do
            echo "[ ## ] copy /mnt/${GRUBCFG[0]} to $line/grub.cfg"
            cp "/mnt/${GRUBCFG[0]}" "$line/grub.cfg"
        done
    fi
    # create new nvram entries
    NEXTX64EFI=$( sed -e "s|/|\\\\|g" <<<"/${GRUBX64EFI[0]}" )
    if [ "x${NEXTX64EFI}" != "x\\EFI\\BOOT\\BOOTX64.EFI" ]; then
        echo "[ ## ] create fallback boot entry for device ${TARGET_DEVICE}, partition ${EFI_PART[0]}"
        efibootmgr -c -d "${TARGET_DEVICE}" -p "${EFI_PART[0]}" -L "${DISTRO_NAME}-fallback" -l "\\EFI\\BOOT\\BOOTX64.EFI" | \
            sed -e '/'"BootOrder\|${DISTRO_NAME}"'/I!d;s/\\/\\\\/g'
    fi
    echo "[ ## ] create ${DISTRO_NAME} boot entry for device ${TARGET_DEVICE}, partition ${EFI_PART[0]}"
    efibootmgr -c -d "${TARGET_DEVICE}" -p "${EFI_PART[0]}" -L "${DISTRO_NAME}" -l "${NEXTX64EFI}" | \
        sed -e '/'"BootOrder\|${DISTRO_NAME}"'/I!d;s/\\/\\\\/g'
    # unmount detected efi filesystem
    sync
    umount -l /mnt
fi

# when raid targets are defined, copy the partition layout to the specified disks and convert to btrfs
RAID_DEVICES=()
while read -r line; do
    if [ -n "$line" ] && [ "x$line" != "xnull" ]; then
        RAID_DEVICES+=( "$line" )
    fi
done <<<"$(yq -r '.setup.raid_targets[]' /var/lib/cloud/instance/config/setup.yml)"
if [ ${#RAID_DEVICES[@]} -gt 0 ]; then
    # use first raid device for filesystem conversion
    mount "${ROOT_PART[0]}" /mnt
    echo "[ .. ] filesystem backup"
    ZSTD_CLEVEL=4 tar -I zstd -cf "${RAID_DEVICES[0]}" -C /mnt .
    umount -l /mnt
    echo "[ .. ] filesystem switch to btrfs"
    dd if=/dev/zero "of=${ROOT_PART[0]}" bs=1M count=16
    mkfs.btrfs "${ROOT_PART[0]}"
    mount -o rw,compress-force=zstd:4 "${ROOT_PART[0]}" /mnt
    echo "[ .. ] filesystem restore"
    ZSTD_CLEVEL=4 tar -I zstd -xf "${RAID_DEVICES[0]}" -C /mnt
    # make debian/ubuntu support btrfs root filesystems
    if [ -f /mnt/bin/apt ]; then
        echo "[ .. ] prepare debian/ubuntu to support btrfs root"
        mount --rbind --make-rslave /dev /mnt/dev
        mount --rbind --make-rslave /sys /mnt/sys
        mount --rbind --make-rslave /proc /mnt/proc
        mount --rbind --make-rslave /run /mnt/run
        mount --rbind --make-rslave /tmp /mnt/tmp
        if [ -n "${BOOT_PART[0]}" ]; then
            mount "${BOOT_PART[1]}" /mnt/boot
        fi
        if [ -n "${EFI_PART[0]}" ]; then
            mount "${EFI_PART[1]}" /mnt/boot/efi
        fi
        GRUB_DEFAULT_CMDLINE="loglevel=3"
        GRUB_GLOBAL_CMDLINE="rootflags=compress-force=zstd:4 console=ttyS0,115200 console=tty1 acpi=force acpi_osi=Linux"
        GRUB_ROOT_UUID="$(lsblk -no MOUNTPOINT,UUID | sed -e '/^\/mnt /!d' | head -n 1 | awk '{ print $2 }')"
        chroot /mnt /bin/bash <<EOS
PATH="\$PATH:/usr/sbin:/sbin"
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y update
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y install btrfs-progs
# is executed by btrfs-progs
# LC_ALL=C DEBIAN_FRONTEND=noninteractive update-initramfs -u
GRUB_CFGS=( /etc/default/grub \$(find /etc/default/grub.d -type f -printf '%p ') )
for cfg in "\${GRUB_CFGS[@]}"; do
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=/#GRUB_CMDLINE_LINUX_DEFAULT=/' "\$cfg" || true
  sed -i 's/^GRUB_CMDLINE_LINUX=/#GRUB_CMDLINE_LINUX=/' "\$cfg" || true
  sed -i 's/^GRUB_DEVICE_UUID=/#GRUB_DEVICE_UUID=/' "\$cfg" || true
  sed -i 's/^GRUB_DISABLE_LINUX_UUID=/#GRUB_DISABLE_LINUX_UUID=/' "\$cfg" || true
  sed -i 's/^GRUB_DISABLE_LINUX_PARTUUID=/#GRUB_DISABLE_LINUX_PARTUUID=/' "\$cfg" || true
  sed -i 's/^GRUB_TERMINAL=/#GRUB_TERMINAL=/' "\$cfg" || true
  sed -i 's/^GRUB_SERIAL_COMMAND=/#GRUB_SERIAL_COMMAND=/' "\$cfg" || true
  sed -i 's/^GRUB_GFXMODE=/#GRUB_GFXMODE=/' "\$cfg" || true
  sed -i 's/^GRUB_GFXPAYLOAD_LINUX=/#GRUB_GFXPAYLOAD_LINUX=/' "\$cfg" || true
  sed -i 's/^GRUB_TIMEOUT_STYLE=/#GRUB_TIMEOUT_STYLE=/' "\$cfg" || true
  sed -i 's/^GRUB_TIMEOUT=/#GRUB_TIMEOUT=/' "\$cfg" || true
  sed -i 's/^GRUB_COLOR_NORMAL=/#GRUB_COLOR_NORMAL=/' "\$cfg" || true
  sed -i 's/^GRUB_COLOR_HIGHLIGHT=/#GRUB_COLOR_HIGHLIGHT=/' "\$cfg" || true
done
tee -a /etc/default/grub <<EOF

# provisioned
GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_DEFAULT_CMDLINE}"
GRUB_CMDLINE_LINUX="${GRUB_GLOBAL_CMDLINE}"
GRUB_DEVICE_UUID="${GRUB_ROOT_UUID}"
GRUB_DISABLE_LINUX_UUID=""
GRUB_DISABLE_LINUX_PARTUUID="true"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=2
GRUB_COLOR_NORMAL="light-gray/black"
GRUB_COLOR_HIGHLIGHT="white/red"
EOF
tee /etc/grub.d/06_override <<EOF
#!/usr/bin/env bash
cat <<'EOX'
set menu_color_normal="light-gray/black"
set menu_color_highlight="white/red"
EOX
EOF
chmod +x /etc/grub.d/06_override
grub-mkconfig -o /boot/grub/grub.cfg
find /boot/efi/EFI -maxdepth 1 -type d -printf '%p\n' | while read -r line; do
    grub-mkconfig -o "\$line/grub.cfg"
done
sed -e 's|.*[[:space:]]/[[:space:]].*|UUID=${GRUB_ROOT_UUID} / btrfs rw,compress-force=zstd:4 0 0|g' -i /etc/fstab
cat /etc/fstab
EOS
        sync
    fi
    # recreate partitions on all raid disks
    echo "[ .. ] copy partition table on all disks"
    for i in "${RAID_DEVICES[@]}"; do
        sgdisk "${TARGET_DEVICE}" -R "${i}"
        echo "[ .. ] update partitions in kernel for ${i}"
        partx -u "${i}"
        sleep 1
        BIOS_RAID_PART=( $(lsblk -no PARTN,PATH,PARTTYPE "${i}" | sed -e '/21686148-6449-6E6F-744E-656564454649/I!d' | head -n1) )
        if [ -n "${BIOS_RAID_PART[0]}" ]; then
            echo "[ .. ] copy bios partition ${BIOS_PART[1]} to ${BIOS_RAID_PART[1]}"
            dd if="${BIOS_PART[1]}" of="${BIOS_RAID_PART[1]}" bs=4096 iflag=fullblock
        fi
        EFI_RAID_PART=( $(lsblk -no PARTN,PATH,PARTTYPE "${i}" | sed -e '/C12A7328-F81F-11D2-BA4B-00A0C93EC93B/I!d' | head -n1) )
        if [ -n "${EFI_RAID_PART[0]}" ]; then
            echo "[ .. ] copy efi partition ${EFI_PART[1]} to ${EFI_RAID_PART[1]}"
            dd if="${EFI_PART[1]}" of="${EFI_RAID_PART[1]}" bs=4096 iflag=fullblock
        fi
        BOOT_RAID_PART=( $(lsblk -no PARTN,PATH,PARTTYPE "${i}" | sed -e '/BC13C2FF-59E6-4262-A352-B275FD6F7172/I!d' | head -n1) )
        if [ -n "${BOOT_RAID_PART[0]}" ]; then
            echo "[ .. ] copy boot partition ${BOOT_PART[1]} to ${BOOT_RAID_PART[1]}"
            dd if="${BOOT_PART[1]}" of="${BOOT_RAID_PART[1]}" bs=4096 iflag=fullblock
        fi
        ROOT_RAID_PART=( $(lsblk -no PATH,PARTN,FSTYPE,PARTTYPE "${i}" | sed -e '/4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709/I!d' | head -n1) )
        if [ -n "${ROOT_RAID_PART[1]}" ]; then
            echo "[ .. ] add root partition ${ROOT_RAID_PART[0]} to array ${ROOT_PART[0]}"
            btrfs device add "${ROOT_RAID_PART[0]}" /mnt
        fi
    done
    echo "[ .. ] rebalance as raid10"
    btrfs balance start -mconvert=raid10 /mnt
    btrfs balance start -dconvert=raid10 /mnt
    btrfs filesystem show /mnt
    df -h /mnt
    echo "[ .. ] sync to disk(s)"
    sync
    umount -R /mnt
    sync
    echo "[ OK ] done"
fi

# mount detected root filesystem
mount "${ROOT_PART[0]}" /mnt

echo "[ ## ] Copy over next kernel and initrd for kexec reboot later"
BOOT_PATH="/mnt/boot"
if [ -n "${BOOT_PART[0]}" ]; then
    mkdir -p /nextboot
    mount "${BOOT_PART[1]}" /nextboot
    BOOT_PATH="/nextboot"
fi
VMLINUZ=$(find "$BOOT_PATH" -maxdepth 1 -name 'vmlinuz*' | sort -Vru | head -n1)
INITRD=$(find "$BOOT_PATH" -maxdepth 1 \( \( -name 'initramfs*' -a ! -name '*fallback*' -a ! -name '*pxe*' \) -o -name 'initrd*' \) | sort -Vru | head -n1)
cp "$VMLINUZ" "$INITRD" /boot/
ls -lh /boot
if [ -d /nextboot ] && mountpoint -q /nextboot; then
    umount -l /nextboot
fi

# prefill package cache
if [ -f /mnt/bin/apt ]; then
    if [ -d /iso/stage/apt ]; then
        mkdir -p /mnt/var/cache/apt /mnt/usr/share/keyrings/
        rsync -av /iso/stage/apt/ /mnt/var/cache/apt/
        rsync -av /iso/stage/keyrings/ /mnt/usr/share/keyrings/
    fi
elif [ -f /mnt/bin/pacman ]; then
    if [ -d /iso/stage/pacman ]; then
        mkdir -p /mnt/var/cache/pacman /mnt/usr/share/keyrings/
        rsync -av /iso/stage/pacman/ /mnt/var/cache/pacman/
        rsync -av /iso/stage/keyrings/ /mnt/usr/share/keyrings/
    fi
elif [ -f /mnt/bin/yum ]; then
    if [ -d /iso/stage/yum ]; then
        mkdir -p /mnt/var/cache/yum /mnt/usr/share/keyrings/
        rsync -av /iso/stage/yum/ /mnt/var/cache/yum/
        rsync -av /iso/stage/keyrings/ /mnt/usr/share/keyrings/
    fi
fi

if [ -d /mnt/swap ]; then
    rm -r /mnt/swap
fi
if [ ${#RAID_DEVICES[@]} -gt 0 ]; then
    # swapfile on a raid is prohibited
    sed -i '/ swap /d' /mnt/etc/fstab
    find /etc/systemd -name "*.swap" | while read -r line; do
        echo "[ OK ] remove swap config $line"
        rm "$line"
    done
else
    # create a 2GiB swap file
    # https://btrfs.readthedocs.io/en/latest/Swapfile.html
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
fi

# write the stage user-data to the cidata directory on disk (only if the image isn't an out-of-the-box ready image)
if [ "xdump" != "x${DISTRO_NAME}" ]; then
  install -d -m 0700 -o root -g root /mnt/cidata
  cp /var/lib/cloud/instance/provision/meta-data /var/lib/cloud/instance/provision/user-data /mnt/cidata/
  chmod 0600 /mnt/cidata/{meta,user}-data
  tee -a /mnt/etc/cloud/cloud.cfg <<EOF

datasource_list: ["NoCloud"]
datasource:
  NoCloud:
    seedfrom: file:///cidata/
EOF
fi

# set local package mirror
PKG_MIRROR=$(yq -r '.setup as $setup | .setup.pkg_mirror[$setup.distro]' /var/lib/cloud/instance/config/setup.yml)
if [ -n "$PKG_MIRROR" ] && [ "xnull" != "x$PKG_MIRROR" ]; then
    if [ -f /mnt/bin/apt ] && grep -q "Debian" /mnt/etc/os-release; then
        [ -f /mnt/etc/apt/sources.list.d/debian.sources ] && \
            tee /mnt/etc/apt/sources.list.d/debian.sources <<<"$PKG_MIRROR" && \
            tee /mnt/etc/apt/sources.list <<<"# see /etc/apt/sources.list.d/debian.sources"
    elif [ -f /mnt/bin/apt ] && grep -q "Ubuntu" /mnt/etc/os-release; then
        [ -f /mnt/etc/apt/sources.list.d/ubuntu.sources ] && \
            tee /mnt/etc/apt/sources.list.d/ubuntu.sources <<<"$PKG_MIRROR" && \
            tee /mnt/etc/apt/sources.list <<<"# see /etc/apt/sources.list.d/ubuntu.sources"
    elif [ -f /mnt/bin/pacman ]; then
        [ -f /mnt/etc/pacman.d/mirrorlist ] && tee /mnt/etc/pacman.d/mirrorlist <<<"$PKG_MIRROR"
    elif [ -f /mnt/bin/yum ]; then
        [ -f /mnt/etc/yum.repos.d/rocky.repo ] && tee /mnt/etc/yum.repos.d/rocky.repo <<<"$PKG_MIRROR"
    fi
fi

# prepare the system to open the luks partition remotely
if [ -n "$ENCRYPT_ENABLED" ] && [[ "$ENCRYPT_ENABLED" =~ [Yy][Ee][Ss] ]] \
    || [[ "$ENCRYPT_ENABLED" =~ [Oo][Nn] ]] || [[ "$ENCRYPT_ENABLED" =~ [Tt][Rr][Uu][Ee] ]]; then
  USERID="$ENCRYPT_SSHUSER"
  USERHASH="$ENCRYPT_SSHHASH"
  tee -a /mnt/etc/passwd <<EOF
$USERID:x:812:812:Remote LUKS unlock and pivot:/:/bin/bash
EOF
  tee -a /mnt/etc/shadow <<EOF
$USERID:$USERHASH::0:99999:7:::
EOF

  mkdir -p /mnt/etc/sudoers.d
  tee "/mnt/etc/sudoers.d/$USERID-luks-unlock" <<EOF
$USERID ALL=(root) NOPASSWD: /usr/local/bin/luks-unlock
EOF

  tee -a /mnt/etc/ssh/sshd_config <<EOF

Match User $USERID
  PasswordAuthentication yes
  PermitTTY yes
  ForceCommand sudo /usr/local/bin/luks-unlock
EOF

  tee /mnt/usr/local/bin/luks-unlock <<EOF
#!/usr/bin/env bash
if [ \$EUID -ne 0 ]; then
  printf "You must run this script with root privileges\n" >&2
  exit 1
fi
if [ -z "\$SUDO_USER" ]; then
  printf "This script has to run as sudo (not root itself)\n" >&2
  exit 1
fi

i=\$((2))
until LC_ALL=C cryptsetup luksOpen --tries 1 ${NEWROOT_PART[0]} nextroot; do
  ret=\$?
  # wrong password
  if [ \$ret -eq 2 ]; then
    printf "Wait \$i seconds...\n" >&2
    sleep "\$i"
    i=\$((i*2))
  # all else means bad things happened
  else
    printf "Abort\n" >&2
    exit 2
  fi
done

mount --mkdir /dev/mapper/nextroot /run/nextroot
sync
if [ -d /run/nextroot/bin ] && [ -d /run/nextroot/etc ] && [ -d /run/nextroot/usr ]; then
  systemctl soft-reboot
else
  printf "No linux root on ${NEWROOT_PART[0]}\n" >&2
  exit 3
fi
EOF
  chmod 0700 /mnt/usr/local/bin/luks-unlock

  # mount encrypted filesystem and prefill it with the tarball under /iso/tar/*.tar.zst
  mount --mkdir /dev/mapper/nextroot /nextroot
  if [ -d /iso/tar ] && [ -f "/iso/tar/${ENCRYPT_IMAGE}" ]; then
    echo ":: Extract tarball /iso/tar/${ENCRYPT_IMAGE}"
    ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -xf "/iso/tar/${ENCRYPT_IMAGE}" -C /nextroot
  fi

  # finalize /nextroot
  sync
  umount -l /nextroot
  cryptsetup luksClose nextroot
  sync
fi

# print the current partition layout of the target device
lsblk -o NAME,PARTN,SIZE,TYPE,LABEL,PARTLABEL,FSTYPE,PARTTYPENAME,UUID "${TARGET_DEVICE}"

# finalize /mnt
sleep 2
sync
cp /cidata_log /mnt/cidata_stage0_log || true
chmod 0600 /mnt/cidata_stage0_log || true
sync
umount -l /mnt

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
