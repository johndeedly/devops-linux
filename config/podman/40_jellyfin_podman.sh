#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable hardware transcoding for jellyfin docker container
mkdir /dev/dri || true
mknod /dev/dri/card0 c 226 0 || true
mknod /dev/dri/renderD128 c 226 128 || true
chmod 666 /dev/dri/card0
chmod 666 /dev/dri/renderD128
mkdir -p /etc/udev/rules.d
tee /etc/udev/rules.d/60-card.rules <<EOF
KERNEL=="card[0-9]*", NAME="dri/%k", GROUP="video", MODE="0666"
EOF
tee /etc/udev/rules.d/60-render.rules <<EOF
KERNEL=="renderD[0-9]*", NAME="dri/%k", GROUP="render", MODE="0666"
EOF

# create jellyfin library folder on host
mkdir /jellyfin || true
chmod 0755 /jellyfin

# enable and start jellyfin
PROJECTNAME="jellyfin"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  config:
  cache:
services:
  main:
    image: jellyfin/jellyfin
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '8096:8096/tcp'
    hostname: '$(</etc/hostname)'
    security_opt:
      - 'no-new-privileges:true'
    devices:
      - '/dev/dri:/dev/dri'
    volumes:
      - config:/config
      - cache:/cache
      - type: bind
        source: /jellyfin
        target: /media
        read_only: true
      - /etc/localtime:/etc/localtime:ro
EOF
pushd "${BUILDTMP}"
  podman-compose up --no-start
popd
pushd /etc/systemd/system
  podman generate systemd --new --name "${PROJECTNAME}_main_1" -f
popd
systemctl enable "container-${PROJECTNAME}_main_1"

firewall-offline-cmd --zone=public --add-port=8096/tcp

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
