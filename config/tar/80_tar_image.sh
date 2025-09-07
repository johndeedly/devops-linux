#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# https://wiki.archlinux.org/title/Full_system_backup_with_tar
EXCLUDE_PATHS=(
  "boot/*" "cidata*" "dev/*" "efi/*" "etc/fstab*" "etc/crypttab*" "etc/systemd/system/cloud-*" "usr/lib/systemd/system/cloud-*"
  "proc/*" "sys/*" "run/*" "mnt/*" "share/*" "srv/pxe/*" "srv/img/*" "srv/tar/*" "media/*" "tmp/*" "swap/*" "var/tmp/*" "var/log/*"
  "var/cache/pacman/pkg/*" "var/cache/apt/*" "var/cache/dnf/*" "var/cache/yum/*" "var/lib/cloud/*" "etc/systemd/system/snapper-*"
  "usr/lib/systemd/system/snapper-*" "etc/systemd/system/timers.target.wants/snapper-*"
  "usr/lib/firmware/*" "root/.ssh/authorized_keys"
)
DISTRO_NAME=$(yq -r '.setup.distro' /var/lib/cloud/instance/config/setup.yml)
mkdir -p /srv/tar
echo "[ ## ] Create tar image"
checked=0
while [ "$checked" -eq 0 ]; do
  ( ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd "${EXCLUDE_PATHS[@]/#/--exclude=}" \
    -cf "/srv/tar/devops-linux-${DISTRO_NAME}.tar.zst" -C / . ) &
  pid=$!
  wait $pid
  echo "[ ## ] Verify tar image"
  if ! ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -xOf "/srv/tar/devops-linux-${DISTRO_NAME}.tar.zst" &> /dev/null; then
    echo "[FAIL] Broken tar image, retry"
    [ -f "/srv/tar/devops-linux-${DISTRO_NAME}.tar.zst" ] && rm "/srv/tar/devops-linux-${DISTRO_NAME}.tar.zst"
  else
    echo "[ OK ] Valid image created"
    checked=1
  fi
done

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
