#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start portainer.io
PROJECTNAME="portainer"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  data:
services:
  main:
    image: portainer/portainer-ce:latest
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '8000:8000'
      - '9000:9000'
      - '9443:9443'
    security_opt:
      - no-new-privileges
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/localtime:/etc/localtime:ro
      - data:/data
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
ufw allow log 8000/tcp comment 'allow portainer'
ufw allow log 9000/tcp comment 'allow portainer'
ufw allow log 9443/tcp comment 'allow portainer'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
[ -f "${0}" ] && rm -- "${0}"
