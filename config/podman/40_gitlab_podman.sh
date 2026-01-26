#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start gitlab
PROJECTNAME="gitlab"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  config:
  logs:
  data:
services:
  main:
    image: gitlab/gitlab-ce:latest
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '8929:80'
      - '2424:22'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://gitlab.example.com:8929'
        gitlab_rails['gitlab_shell_ssh_port'] = 2424
    volumes:
      - config:/etc/gitlab
      - logs:/var/log/gitlab
      - data:/var/opt/gitlab
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
ufw allow log 8929/tcp comment 'allow gitlab'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
[ -f "${0}" ] && rm -- "${0}"
