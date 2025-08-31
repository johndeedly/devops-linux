#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# https://wiki.archlinux.org/title/Full_system_backup_with_tar
DISTRO_NAME=$(yq -r '.setup.distro' /var/lib/cloud/instance/config/setup.yml)
mkdir -p /srv/tar
ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd \
  --exclude="./boot/efi" --exclude="./cidata*" --exclude="./dev/*" --exclude="./efi" --exclude="./etc/fstab*" --exclude="./etc/crypttab*" --exclude="./etc/systemd/system/cloud-*" --exclude="./usr/lib/systemd/system/cloud-*" --exclude="./proc/*" --exclude="./sys/*" --exclude="./run/*" --exclude="./mnt/*" --exclude="./share/*" --exclude="./srv/pxe" --exclude="./srv/img" --exclude="./srv/tar" --exclude="./media/*" --exclude="./tmp/*" --exclude="./swap/*" --exclude="./usr/lib/firmware/*" --exclude="./var/tmp/*" --exclude="./var/log/*" --exclude="./var/cache/pacman/pkg/*" --exclude="./var/cache/apt/*" --exclude="./var/lib/cloud/*" \
  --acls --xattrs -cpaf "/srv/tar/devops-linux-${DISTRO_NAME}.tar.zst" -C / .

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
