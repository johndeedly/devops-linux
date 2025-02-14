#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start postgres
PROJECTNAME="postgres"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  db-data:
  pgadm-data:
services:
  database:
    image: postgres:latest
    restart: unless-stopped
    networks:
      - lan
    ports:
      - 5432:5432
    security_opt:
      - no-new-privileges:true
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: resu
      POSTGRES_DB: default
    volumes:
      - db-data:/var/lib/postgresql/data
  pgadmin:
    image: dpage/pgadmin4
    restart: unless-stopped
    networks:
      - lan
    ports:
      - 15432:80
    depends_on:
      - database
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
  podman generate systemd --new --name "${PROJECTNAME}_database_1" -f
  podman generate systemd --new --name "${PROJECTNAME}_pgadmin_1" \
    "--after=container-${PROJECTNAME}_database_1.service" \
    "--requires=container-${PROJECTNAME}_database_1.service" -f
popd
systemctl enable "container-${PROJECTNAME}_pgadmin_1"

firewall-offline-cmd --zone=public --add-port=5432/tcp
firewall-offline-cmd --zone=public --add-port=15432/tcp

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
