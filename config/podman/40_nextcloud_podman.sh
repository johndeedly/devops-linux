#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start nextcloud
PROJECTNAME="nextcloud"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  frontend:
volumes: 
  nextcloud_aio_mastercontainer:
    name: nextcloud_aio_mastercontainer
services:
  main:
    image: ghcr.io/nextcloud-releases/all-in-one:latest
    restart: unless-stopped
    init: true
    name: nextcloud-aio-mastercontainer
    networks:
      - frontend
    ports:
      - '80:80'
      - '8080:8080'
      - '8443:8443'
    environment:
      APACHE_PORT: 11000
      APACHE_IP_BINDING: 127.0.0.1
      APACHE_ADDITIONAL_NETWORK: frontend
      SKIP_DOMAIN_VALIDATION: true
    volumes:
      - nextcloud_aio_mastercontainer:/mnt/docker-aio-config
      - /var/run/docker.sock:/var/run/docker.sock:ro
EOF
pushd "${BUILDTMP}"
  podman-compose up --no-start
popd
pushd /etc/systemd/system
  podman generate systemd --new --name "nextcloud-aio-mastercontainer" -f
popd
systemctl enable "container-nextcloud-aio-mastercontainer"

firewall-offline-cmd --zone=public --add-port=80/tcp
firewall-offline-cmd --zone=public --add-port=8080/tcp
firewall-offline-cmd --zone=public --add-port=8443/tcp

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
