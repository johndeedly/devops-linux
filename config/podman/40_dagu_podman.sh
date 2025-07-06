#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start dagu
PROJECTNAME="dagu"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

mkdir "${BUILDTMP}/dagu"
tee "${BUILDTMP}/dagu/example.yaml" <<'EOF'
# https://github.com/dagu-org/dagu?tab=readme-ov-file#minimal-examples

params:
  - NAME: "Dagu"

steps:
  - name: Hello world
    command: echo Hello $NAME
  - name: Done
    command: echo Done!
    depends:
      - Hello world
EOF
tee "${BUILDTMP}/dagu/Dockerfile" <<EOF
FROM ghcr.io/dagu-org/dagu:latest

COPY ./example.yaml /config/dags/
EOF


tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  config:
services:
  main:
    build: ./dagu
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '18080:8080'
    security_opt:
      - 'no-new-privileges:true'
    environment:
      DAGU_TZ: CET
      DAGU_PORT: 8080
      DAGU_IS_BASICAUTH: 1
      DAGU_BASICAUTH_USERNAME: user
      DAGU_BASICAUTH_PASSWORD: resu
    volumes:
      - config:/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/localtime:/etc/localtime:ro
    command: dagu start-all
EOF
pushd "${BUILDTMP}"
  podman-compose up --no-start
popd
pushd /etc/systemd/system
  podman generate systemd --new --name "${PROJECTNAME}_main_1" -f
popd
systemctl enable "container-${PROJECTNAME}_main_1"

ufw disable
ufw allow log 18080/tcp comment 'allow dagu'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
