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
# debian and ubuntu versions are old per design
skip-test=LYNIS
# pxe boot needs special attention
skip-test=BOOT-5122
# /var and /home shall be on the same partition
skip-test=FILE-6310
# usb drivers are needed
skip-test=USB-1000
# firewire drivers are needed
skip-test=STRG-1846
# not part of a domain
skip-test=NAME-4028
# /etc/hosts contains FQDN names, duh...
skip-test=NAME-4404
# security updates are always included in unattended upgrades
skip-test=PKGS-7320
# security updates are always included in unattended upgrades
skip-test=PKGS-7398
# no fiddling around with port 22/ssh
skip-test=SSH-7408:port
# automation tools are everywhere
skip-test=TOOL-5002
# kernel module loading is needed
skip-test=KRNL-6000:kernel.modules_disabled
# passwords lasts as long as the user wants to - this does not increase security just by enforcing it [1]
skip-test=AUTH-9282
# passwords lasts as long as the user wants to - this does not increase security just by enforcing it [1]
skip-test=AUTH-9286
# because it is configured this way
skip-test=KRNL-5788
# the security repository is configured
skip-test=PKGS-7388
# ufw leaves rules empty when not used
skip-test=FIRE-4513
# why should I warn unauthorized users?! Do they crap their pants when they read "please don't do this"?!
skip-test=BANN-7126
# why should I warn unauthorized users?! Do they crap their pants when they read "please don't do this"?!
skip-test=BANN-7130
# when file integrity is compromised, automation rebuilds it, backups restore it
skip-test=FINT-4350
# apt-listbugs has no installation candidate on ubuntu: skipping, as unattended-upgrades does the job for you
skip-test=DEB-0810

# [1]: security_considerations_when_using_password_policies.md "Question regarding the hardening of a computer system by enforcing a timed rotation policy on passwords"
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
