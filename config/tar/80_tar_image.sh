#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install squashfs-tools
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed squashfs-tools
fi

EXCLUDE_PATHS=(
  "boot/*" "cidata*" "dev/*" "efi/*" "etc/fstab*" "etc/crypttab*" "etc/systemd/system/cloud-*" "usr/lib/systemd/system/cloud-*"
  "proc/*" "sys/*" "run/*" "mnt/*" "share/*" "srv/pxe/*" "srv/img/*" "srv/tar/*" "media/*" "tmp/*" "swap/*" "var/tmp/*" "var/log/*"
  "var/cache/pacman/pkg/*" "var/cache/apt/*" "var/cache/dnf/*" "var/cache/yum/*" "var/lib/cloud/*" "etc/systemd/system/snapper-*"
  "usr/lib/systemd/system/snapper-*" "etc/systemd/system/timers.target.wants/snapper-*"
  "root/.ssh/authorized_keys"
)
mkdir -p "/var/tmp/sfs/mnt"
sync
echo "[ ## ] Create squashfs image of rootfs"
( mksquashfs / "/var/tmp/sfs/rootfs.img" -comp zstd -Xcompression-level 4 -b 1M -progress -wildcards -e "${EXCLUDE_PATHS[@]}" ) &
pid=$!
wait $pid
mount -t squashfs -o loop /var/tmp/sfs/rootfs.img /var/tmp/sfs/mnt

# https://wiki.archlinux.org/title/Full_system_backup_with_tar
DISTRO_NAME=$(yq -r '.setup.distro' /var/lib/cloud/instance/config/setup.yml)
TMP_OPTS=( "" $(yq -r '.setup.options[]' /var/lib/cloud/instance/config/setup.yml) )
SETUP_OPTIONS=$(IFS='-'; echo "${TMP_OPTS[*]}")
mkdir -p /srv/tar
echo "[ ## ] Create tar image of squashfs root"
checked=0
while [ "$checked" -eq 0 ]; do
  ( ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -cf "/srv/tar/devops-linux-${DISTRO_NAME}${SETUP_OPTIONS}.tar.zst" -C /var/tmp/sfs/mnt . ) &
  pid=$!
  wait $pid
  echo "[ ## ] Verify tar image"
  if ! ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -xOf "/srv/tar/devops-linux-${DISTRO_NAME}${SETUP_OPTIONS}.tar.zst" &> /dev/null; then
    echo "[FAIL] Broken tar image, retry"
    [ -f "/srv/tar/devops-linux-${DISTRO_NAME}${SETUP_OPTIONS}.tar.zst" ] && rm "/srv/tar/devops-linux-${DISTRO_NAME}${SETUP_OPTIONS}.tar.zst"
  else
    echo "[ OK ] Valid image created"
    checked=1
  fi
done
umount -l /var/tmp/sfs/mnt

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
