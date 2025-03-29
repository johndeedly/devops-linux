#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable hardware transcoding for plex docker container
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

# enable and start plex
PROJECTNAME="plex"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  config:
  transcode:
  data:
services:
  main:
    image: plexinc/pms-docker
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '32400:32400/tcp'
      - '8324:8324/tcp'
      - '32469:32469/tcp'
      - '1900:1900/udp'
      - '32410:32410/udp'
      - '32412:32412/udp'
      - '32413:32413/udp'
      - '32414:32414/udp'
    hostname: '$(</etc/hostname)'
    security_opt:
      - 'no-new-privileges:true'
    devices:
      - '/dev/dri:/dev/dri'
    environment:
      TZ: CET
      ADVERTISE_IP: 'http://$(</etc/hostname):32400/'
    volumes:
      - config:/config
      - transcode:/transcode
      - data:/data
      - /etc/localtime:/etc/localtime:ro
EOF
pushd "${BUILDTMP}"
  podman-compose up --no-start
popd
pushd /etc/systemd/system
  podman generate systemd --new --name "${PROJECTNAME}_main_1" -f
popd
systemctl enable "container-${PROJECTNAME}_main_1"

firewall-offline-cmd --zone=public --add-port=32400/tcp
firewall-offline-cmd --zone=public --add-port=8324/tcp
firewall-offline-cmd --zone=public --add-port=32469/tcp
firewall-offline-cmd --zone=public --add-port=1900/udp
firewall-offline-cmd --zone=public --add-port=32410/udp
firewall-offline-cmd --zone=public --add-port=32412/udp
firewall-offline-cmd --zone=public --add-port=32413/udp
firewall-offline-cmd --zone=public --add-port=32414/udp

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
