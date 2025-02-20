#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start dagu
PROJECTNAME="dagu"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  config:
services:
  main:
    image: ghcr.io/dagu-org/dagu:latest
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '18080:8080'
    security_opt:
      - 'no-new-privileges:true'
    environment:
      DAGU_TZ: CET
    volumes:
      - config:/config
    command: dagu start-all
EOF
pushd "${BUILDTMP}"
  podman-compose up --no-start
popd
pushd /etc/systemd/system
  podman generate systemd --new --name "${PROJECTNAME}_main_1" -f
popd
systemctl enable "container-${PROJECTNAME}_main_1"

firewall-offline-cmd --zone=public --add-port=18080/tcp

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
