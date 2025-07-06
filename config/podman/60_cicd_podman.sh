#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

mkdir /deploy

# enable and start ci-cd container
PROJECTNAME="cicd"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

mkdir "${BUILDTMP}/cicd"
tee "${BUILDTMP}/cicd/run-build.sh" <<'EOF'
#!/bin/bash

LC_ALL=C yes | LC_ALL=C pacman -Syu --noconfirm --needed findutils git yq xorriso moreutils cloud-image-utils

git clone https://github.com/johndeedly/devops-linux.git

pushd devops-linux
  LOGCOUNT=$(git log --oneline | wc -l)

  # cleanup
  find /deploy -name "*.iso" -print | while read -r line; do
    rm "$line"
  done

  # archlinux base
  yq -y '(.setup.distro) = "archlinux"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/archlinux-base-x86_64-r${LOGCOUNT}.iso"
  fi

  # archlinux mirror
  yq -y '(.setup.distro) = "archlinux"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["mirror"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/archlinux-mirror-x86_64-r${LOGCOUNT}.iso"
  fi

  # archlinux kde
  yq -y '(.setup.distro) = "archlinux"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","kde"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/archlinux-kde-x86_64-r${LOGCOUNT}.iso"
  fi

  # archlinux kde pxe-image
  yq -y '(.setup.distro) = "archlinux"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","kde","pxe-image"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/archlinux-kde-pxe-x86_64-r${LOGCOUNT}.iso"
  fi

  # debian 12 base
  yq -y '(.setup.distro) = "debian-12"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-12-base-x86_64-r${LOGCOUNT}.iso"
  fi

  # debian 12 mirror
  yq -y '(.setup.distro) = "debian-12"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["mirror"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-12-mirror-x86_64-r${LOGCOUNT}.iso"
  fi

  # debian 12 kde
  yq -y '(.setup.distro) = "debian-12"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","kde"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-12-kde-x86_64-r${LOGCOUNT}.iso"
  fi

  # debian 12 kde pxe-image
  yq -y '(.setup.distro) = "debian-12"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","kde","pxe-image"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-12-kde-pxe-x86_64-r${LOGCOUNT}.iso"
  fi

  # debian 12 proxmox
  yq -y '(.setup.distro) = "debian-12"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","proxmox","proxmox-devops"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-12-proxmox-x86_64-r${LOGCOUNT}.iso"
  fi

  # debian 12 podman
  yq -y '(.setup.distro) = "debian-12"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","podman"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-12-podman-x86_64-r${LOGCOUNT}.iso"
  fi

  # ubuntu 24 base
  yq -y '(.setup.distro) = "ubuntu-24"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/ubuntu-24-base-x86_64-r${LOGCOUNT}.iso"
  fi

  # ubuntu 24 mirror
  yq -y '(.setup.distro) = "ubuntu-24"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["mirror"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/ubuntu-24-mirror-x86_64-r${LOGCOUNT}.iso"
  fi

  # ubuntu 24 kde
  yq -y '(.setup.distro) = "ubuntu-24"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","kde"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/ubuntu-24-kde-x86_64-r${LOGCOUNT}.iso"
  fi

  # ubuntu 24 kde pxe-image
  yq -y '(.setup.distro) = "ubuntu-24"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","kde","pxe-image"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/ubuntu-24-kde-pxe-x86_64-r${LOGCOUNT}.iso"
  fi
popd

ls -la /deploy
EOF
tee "${BUILDTMP}/cicd/Dockerfile" <<'EOF'
FROM archlinux

WORKDIR /app
COPY ./run-build.sh /app/
RUN chmod +x /app/run-build.sh

VOLUME /deploy
CMD ["/app/run-build.sh"]
EOF

mkdir "${BUILDTMP}/nginx"
tee "${BUILDTMP}/nginx/Dockerfile" <<'EOF'
FROM nginx

RUN sed -i 's/index.*;/autoindex on; autoindex_exact_size off; autoindex_format html;/g' /etc/nginx/conf.d/default.conf
EOF

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
services:
  main:
    build: ./cicd
    restart: on-failure
    networks:
      - lan
    security_opt:
      - 'no-new-privileges:true'
    volumes:
      - /deploy:/deploy
  web:
    build: ./nginx
    restart: on-failure
    networks:
      - lan
    security_opt:
      - 'no-new-privileges:true'
    ports:
      - '6080:80'
    volumes:
      - /deploy:/usr/share/nginx/html:ro
EOF
pushd "${BUILDTMP}"
  podman-compose up --no-start
popd
pushd /etc/systemd/system
  podman generate systemd --new --name "${PROJECTNAME}_main_1" -f
  podman generate systemd --new --name "${PROJECTNAME}_web_1" -f
popd
systemctl enable "container-${PROJECTNAME}_main_1"
systemctl enable "container-${PROJECTNAME}_web_1"

# weekly execution
tee "/etc/systemd/system/container-${PROJECTNAME}_main_1.timer" <<EOF
[Unit]
Description=Weekly CI/CD job

[Timer]
OnCalendar=weekly
AccuracySec=12h
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl enable "container-${PROJECTNAME}_main_1.timer"

ufw disable
ufw allow log 6080/tcp comment 'allow cicd'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
