#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# disable systemd-network-generator in pxe image
systemctl mask systemd-network-generator

# create a squashfs snapshot based on rootfs
LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed squashfs-tools
mkdir -p /srv/img
sync
mksquashfs / /srv/img/rootfs.img -comp zstd -Xcompression-level 4 -b 1M -progress -wildcards \
  -e "boot/*" "cidata*" "dev/*" "etc/fstab" "etc/crypttab" "etc/crypttab.initramfs" "proc/*" "sys/*" "run/*" "mnt/*" "share/*" "srv/pxe/*" "media/*" "tmp/*" "usr/lib/firmware/*" "var/tmp/*" "var/log/*" "var/cache/pacman/pkg/*"

# reenable systemd-network-generator
systemctl unmask systemd-network-generator

LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed buildah podman fuse-overlayfs yq

export TMPDIR="/var/tmp/buildah/tmp"
mkdir -p "${TMPDIR}" /var/tmp/buildah/run/storage /var/tmp/buildah/var/storage
sed -i 's|/run/containers/storage|/var/tmp/buildah/run/storage|g' /etc/containers/storage.conf
sed -i 's|/var/lib/containers/storage|/var/tmp/buildah/var/storage|g' /etc/containers/storage.conf
buildah info

buildah --cap-add=SYS_CHROOT,NET_ADMIN,NET_RAW --name worker from scratch
buildah config --entrypoint "/usr/sbin/init" --cmd '["--log-level=info", "--unit=multi-user.target"]' worker
scratchmnt=$(buildah mount worker)
mount --bind "${scratchmnt}" /mnt

pushd /mnt
unsquashfs -d . /srv/img/rootfs.img
popd

sync
fuser -km /mnt || true
sync
umount /mnt || true
buildah umount worker

DISTRO_NAME=$(yq -r '.setup.distro' /var/lib/cloud/instance/config/setup.yml)
buildah commit worker "devops-linux-${DISTRO_NAME}"

mkdir -p /srv/docker
buildah push "devops-linux-${DISTRO_NAME}" "docker-archive:/srv/docker/devops-linux-${DISTRO_NAME}.tar"
zstd -4 "/srv/docker/devops-linux-${DISTRO_NAME}.tar"
buildah rm worker
