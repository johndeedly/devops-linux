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

LC_ALL=C yes | LC_ALL=C pacman -Syu --noconfirm --needed git yq xorriso moreutils cloud-image-utils

git clone https://github.com/johndeedly/devops-linux.git

pushd devops-linux
  LOGCOUNT=$(git log --oneline | wc -l)

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

  # debian base
  yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-base-x86_64-r${LOGCOUNT}.iso"
  fi

  # debian mirror
  yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["mirror"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-mirror-x86_64-r${LOGCOUNT}.iso"
  fi
  
  # debian kde
  yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","kde"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-kde-x86_64-r${LOGCOUNT}.iso"
  fi

  # debian kde pxe-image
  yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","kde","pxe-image"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-kde-pxe-x86_64-r${LOGCOUNT}.iso"
  fi

  # debian proxmox
  yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","proxmox","proxmox-devops"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-proxmox-x86_64-r${LOGCOUNT}.iso"
  fi

  # debian podman
  yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.options) = ["base","podman"]' config/setup.yml | sponge config/setup.yml
  yq -y '(.setup.target) = "auto"' config/setup.yml | sponge config/setup.yml
  if ./cidata.sh --archiso; then
    mv archlinux-x86_64-cidata.iso "/deploy/debian-podman-x86_64-r${LOGCOUNT}.iso"
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
EOF
pushd "${BUILDTMP}"
  podman-compose up --no-start
popd
pushd /etc/systemd/system
  podman generate systemd --new --name "${PROJECTNAME}_main_1" -f
popd
systemctl enable "container-${PROJECTNAME}_main_1"

# daily execution
tee "/etc/systemd/system/container-${PROJECTNAME}_main_1.timer" <<EOF
[Unit]
Description=Daily CI/CD job

[Timer]
OnCalendar=daily
AccuracySec=12h
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl enable "container-${PROJECTNAME}_main_1.timer"

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
