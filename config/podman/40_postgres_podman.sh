#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start postgres
PROJECTNAME="postgres"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

mkdir "${BUILDTMP}/pgadmin"
tee "${BUILDTMP}/pgadmin/servers.json" <<EOF
{
  "Servers": {
    "1": {
      "Name": "Database",
      "Group": "Servers",
      "Port": 5432,
      "Username": "user",
      "Host": "postgres",
      "SSLMode": "prefer",
      "MaintenanceDB": "postgres"
    }
  }
}
EOF
tee "${BUILDTMP}/pgadmin/Dockerfile" <<EOF
FROM dpage/pgadmin4:latest

COPY ./servers.json /pgadmin4/servers.json
EOF


tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  db-data:
  pgadm-data:
services:
  postgres:
    image: postgres:alpine
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '5432:5432'
    security_opt:
      - 'no-new-privileges:true'
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: resu
      POSTGRES_DB: default
    volumes:
      - db-data:/var/lib/postgresql/data
  pgadmin:
    build: ./pgadmin
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '15432:80'
    environment:
      PGADMIN_DEFAULT_EMAIL: user@lan.internal
      PGADMIN_DEFAULT_PASSWORD: resu
    volumes:
      - pgadm-data:/var/lib/pgadmin
EOF
pushd "${BUILDTMP}"
  podman-compose up --no-start
popd
pushd /etc/systemd/system
  podman generate systemd --new --name "${PROJECTNAME}_postgres_1" -f
  podman generate systemd --new --name "${PROJECTNAME}_pgadmin_1" \
    "--after=container-${PROJECTNAME}_postgres_1.service" \
    "--requires=container-${PROJECTNAME}_postgres_1.service" -f
popd
systemctl enable "container-${PROJECTNAME}_postgres_1"
systemctl enable "container-${PROJECTNAME}_pgadmin_1"

ufw disable
ufw allow log 5432/tcp comment 'allow postgres'
ufw allow log 15432/tcp comment 'allow postgres'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
