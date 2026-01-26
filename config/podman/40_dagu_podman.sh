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

COPY ./example.yaml /var/lib/dagu/dags/
EOF


tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  dagu-data:
services:
  main:
    build: ./dagu
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '18080:8080'
    security_opt:
      - no-new-privileges
    environment:
      DAGU_HOST: 0.0.0.0
      DAGU_PORT: 8080
      DAGU_DAGS_DIR: /var/lib/dagu/dags
      DAGU_AUTH_MODE: builtin
      DAGU_AUTH_TOKEN_SECRET: zPUoo42BSRpwWdfgvqDEKQBcDXNStKLvPBKqb4htAVCETGq8mqVtGygbkIDzb0Ni8Cmbos5xqpIXQX0WXpTLo7uAQiGNRSBNBTZR1RjimdU4vPWM0gf1HYc6yiJPkwOP
      DAGU_AUTH_ADMIN_USERNAME: dagu
      # minimum password length is 8 characters (not documented)
      DAGU_AUTH_ADMIN_PASSWORD: daguadmin
      DAGU_AUTH_TOKEN_TTL: 24h
      DAGU_TZ: CET
    volumes:
      - dagu-data:/var/lib/dagu
      # For Docker in Docker (DinD) support, mount the host Docker socket
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/localtime:/etc/localtime:ro
    command: ["dagu", "start-all"]
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
ufw allow log 18080/tcp comment 'allow dagu'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
[ -f "${0}" ] && rm -- "${0}"
