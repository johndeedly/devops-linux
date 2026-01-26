#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start homeassistant
PROJECTNAME="homeassistant"
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
    image: ghcr.io/home-assistant/home-assistant:stable
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '8123:8123'
    security_opt:
      - no-new-privileges
    volumes:
      - config:/config
      - /etc/localtime:/etc/localtime:ro
EOF
pushd "${BUILDTMP}"
  podman-compose up --no-start
  mkdir -p /etc/containers/systemd
  /root/.cargo/bin/podlet --install --unit-directory generate container "${PROJECTNAME}_main_1"
  ls -la /etc/containers/systemd
popd
systemctl daemon-reload
systemctl preset "${PROJECTNAME}_main_1.service"

ufw disable
ufw allow log 8123/tcp comment 'allow homeassistant'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
[ -f "${0}" ] && rm -- "${0}"
