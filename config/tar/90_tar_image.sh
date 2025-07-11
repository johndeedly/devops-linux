#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# create a squashfs snapshot based on rootfs
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install squashfs-tools
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed squashfs-tools
fi
mkdir -p /srv/img /srv/data /srv/tar
sync
mksquashfs / /srv/img/rootfs.img -comp zstd -Xcompression-level 4 -b 1M -progress -wildcards \
  -e "boot/efi/*" "cidata*" "dev/*" "efi/*" "etc/fstab*" "etc/crypttab*" "etc/systemd/system/cloud-*" "usr/lib/systemd/system/cloud-*" "proc/*" "sys/*" "run/*" "mnt/*" "share/*" "srv/pxe/*" "srv/img/*" "media/*" "tmp/*" "swap/*" "usr/lib/firmware/*" "var/tmp/*" "var/log/*" "var/cache/pacman/pkg/*" "var/cache/apt/*" "var/lib/cloud/*"

DISTRO_NAME=$(yq -r '.setup.distro' /var/lib/cloud/instance/config/setup.yml)
pushd /srv/data
  unsquashfs -d . /srv/img/rootfs.img
  rm -r boot/efi || true
  rm -r dev || true
  rm -r efi || true
  rm -r proc || true
  rm -r sys || true
  rm -r run || true
  find . \( -type f -o -type l \) -printf '%P\0' | ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -cf "/srv/tar/devops-linux-${DISTRO_NAME}.tar.zst" --null --files-from=-
popd

# sync everything to disk
sync

# cleanup
rm -- "${0}"
