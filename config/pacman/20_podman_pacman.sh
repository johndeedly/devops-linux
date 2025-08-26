#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed podman-docker podman-compose docker-compose fuse-overlayfs \
    btrfs-progs cockpit-podman

mkdir -p /etc/containers/registries.conf.d
tee /etc/containers/registries.conf.d/10-unqualified-search-registries.conf <<EOF
unqualified-search-registries = ["docker.io"]
EOF
tee /etc/containers/registries.conf.d/05-shortnames.conf <<EOF
$(curl -sL 'https://raw.githubusercontent.com/containers/shortnames/refs/heads/main/shortnames.conf')
EOF

# Enable all configured services
systemctl enable podman.service podman.socket

# allow forwarding to all private networks
ufw disable
ufw route allow from any to 10.0.0.0/8 comment 'allow fwd to private net'
ufw route allow from any to 172.16.0.0/12 comment 'allow fwd to private net'
ufw route allow from any to 192.168.0.0/16 comment 'allow fwd to private net'
ufw route allow from any to fe80::/64 comment 'allow fwd to private net'
ufw route allow from any to fc00::/7 comment 'allow fwd to private net'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
