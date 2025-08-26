#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# install needed packages
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y install lynis colorized-logs
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --needed --noconfirm lynis python-ansi2html
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C dnf install -y lynis colorized-logs
fi

# create a profile to include custom options
tee /etc/lynis/custom.prf <<EOF
# provision user (uid 0) is removed at the end
skip-test=AUTH-9204
skip-test=AUTH-9208
EOF

# perform a security audit
DISTRO_NAME=$(yq -r '.setup.distro' /var/lib/cloud/instance/config/setup.yml)
AUDIT_DATE=$(date +%F)
LOG_FILE_ANSI="/srv/audit/lynis-report-${DISTRO_NAME}-${AUDIT_DATE}.log"
LOG_FILE_DAT="/srv/audit/lynis-report-${DISTRO_NAME}-${AUDIT_DATE}.dat"
LOG_FILE_HTML="/srv/audit/lynis-report-${DISTRO_NAME}-${AUDIT_DATE}.html"
mkdir -p /srv/audit
LC_ALL=C LANG="en" lynis audit system | tee "${LOG_FILE_ANSI}"
cat "${LOG_FILE_ANSI}" | LC_ALL=C ansi2html > "${LOG_FILE_HTML}"
cp /var/log/lynis-report.dat "${LOG_FILE_DAT}"

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
