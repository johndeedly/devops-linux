#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install podman-docker podman-compose docker-compose fuse-overlayfs \
    btrfs-progs cockpit-podman firewalld

mkdir -p /etc/containers/registries.conf.d
tee /etc/containers/registries.conf.d/10-unqualified-search-registries.conf <<EOF
unqualified-search-registries = ["docker.io"]
EOF
tee /etc/containers/registries.conf.d/05-shortnames.conf <<EOF
$(curl -sL 'https://raw.githubusercontent.com/containers/shortnames/refs/heads/main/shortnames.conf')
EOF

# Enable all configured services
systemctl enable podman.service podman.socket

# sync everything to disk
sync

# cleanup
rm -- "${0}"
