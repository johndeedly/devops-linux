#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed xkcdpass

# enable and start nextcloud
PROJECTNAME="nextcloud"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

ROOTPASSWD=$(xkcdpass -w ger-anlx -d '' -v '[A-Xa-x]' --min=4 --max=8 -n 6)
PASSWDGEN=$(xkcdpass -w ger-anlx -d '' -v '[A-Xa-x]' --min=4 --max=8 -n 6)

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  nextcloud:
  db:
services:
  db:
    image: mariadb:10.6
    command: --transaction-isolation=READ-COMMITTED --log-bin=binlog --binlog-format=ROW
    restart: unless-stopped
    volumes:
      - db:/var/lib/mysql
    networks:
      - lan
    environment:
      MYSQL_ROOT_PASSWORD: ${ROOTPASSWD}
      MYSQL_PASSWORD: ${PASSWDGEN}
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
  main:
    image: nextcloud
    ports:
      - 8080:80
    depends-on:
      - db
    links:
      - db
    networks:
      - lan
    volumes:
      - nextcloud:/var/www/html
    environment:
      MYSQL_PASSWORD: ${PASSWDGEN}
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_HOST: db
    restart: unless-stopped
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
ufw allow log 8080/tcp comment 'allow nextcloud'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
[ -f "${0}" ] && rm -- "${0}"
