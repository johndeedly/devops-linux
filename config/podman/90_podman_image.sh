#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# disable systemd-network-generator in pxe image
systemctl mask systemd-network-generator

# disable sleep
sed -i 's/^#\?HandleSuspendKey=.*/HandleSuspendKey=poweroff/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleHibernateKey=.*/HandleHibernateKey=poweroff/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=poweroff/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=poweroff/' /etc/systemd/logind.conf
sed -i 's/^#\?AllowSuspend=.*/AllowSuspend=no/' /etc/systemd/sleep.conf
systemctl mask suspend.target

# create a squashfs snapshot based on rootfs
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install squashfs-tools
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed squashfs-tools
fi
mkdir -p /srv/img
sync
mksquashfs / /srv/img/rootfs.img -comp zstd -Xcompression-level 4 -b 1M -progress -wildcards \
  -e "boot/*" "cidata*" "dev/*" "efi/*" "etc/fstab*" "etc/crypttab*" "etc/systemd/system/cloud-*" "usr/lib/systemd/system/cloud-*" "proc/*" "sys/*" "run/*" "mnt/*" "share/*" "srv/pxe/*" "srv/img/*" "media/*" "tmp/*" "swap/*" "usr/lib/firmware/*" "var/tmp/*" "var/log/*" "var/cache/pacman/pkg/*" "var/cache/apt/*" "var/lib/cloud/*"

# reenable sleep
sed -i 's/^#\?HandleSuspendKey=.*/HandleSuspendKey=suspend/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleHibernateKey=.*/HandleHibernateKey=suspend/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=suspend/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf
sed -i 's/^#\?AllowSuspend=.*/AllowSuspend=yes/' /etc/systemd/sleep.conf
systemctl unmask suspend.target

# reenable systemd-network-generator
systemctl unmask systemd-network-generator

if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install buildah podman fuse-overlayfs yq
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed buildah podman fuse-overlayfs yq
fi

export TMPDIR="/var/tmp/buildah/tmp"
mkdir -p "${TMPDIR}" /var/tmp/buildah/run/storage /var/tmp/buildah/var/storage
sed -i 's|/run/containers/storage|/var/tmp/buildah/run/storage|g' /etc/containers/storage.conf
sed -i 's|/var/lib/containers/storage|/var/tmp/buildah/var/storage|g' /etc/containers/storage.conf
buildah info

# see https://developers.redhat.com/blog/2016/09/13/running-systemd-in-a-non-privileged-container#the_quest
buildah --cap-add=SYS_CHROOT,NET_RAW,MKNOD --name worker from scratch
buildah config --entrypoint '["/usr/lib/systemd/systemd", "--log-level=info", "--unit=multi-user.target"]' \
  --stop-signal 'SIGRTMIN+3' --workingdir "/root" --port '22/tcp' --port '9090/tcp' \
  --user "root:root" --volume "/run" --volume "/tmp" --volume "/sys/fs/cgroup" worker
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

# create docker compose
# BUG in systemd with resolved: https://github.com/systemd/systemd/issues/34565
# resolved fails instead of silently exiting
# will be fixed in systemd version 258
tee "/srv/docker/docker-compose-${DISTRO_NAME}.yml" <<EOF
name: ${DISTRO_NAME}
networks:
  lan:
services:
  main:
    image: localhost/devops-linux-${DISTRO_NAME}
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '2221:22/tcp'
      - '9091:9090/tcp'
    stop_signal: SIGRTMIN+3
    cap_add:
      - SYS_CHROOT
      - NET_RAW
      - MKNOD
    tty: true
    volumes:
      - type: tmpfs
        target: /run
        tmpfs:
          mode: 755
      - type: tmpfs
        target: /tmp
        tmpfs:
          mode: 1777
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
EOF

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
