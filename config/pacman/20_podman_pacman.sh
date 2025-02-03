#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed podman-docker podman-compose docker-compose fuse-overlayfs \
    btrfs-progs portainer-bin cockpit-podman

# Enable all configured services
systemctl enable podman portainer

firewall-offline-cmd --zone=public --add-port=8000/tcp
firewall-offline-cmd --zone=public --add-port=9000/tcp
firewall-offline-cmd --zone=public --add-port=9443/tcp

# sync everything to disk
sync

# cleanup
rm -- "${0}"
