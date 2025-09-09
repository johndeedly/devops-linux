#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

SYSLOG_SERVER_ENABLED="$(yq -r '.setup.logserver.enabled' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_LOGFILE="$(yq -r '.setup.logserver.logfile' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_BIND_IP="$(yq -r '.setup.logserver.bind_ip' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_BIND_PORT="$(yq -r '.setup.logserver.bind_port' /var/lib/cloud/instance/config/setup.yml)"

if [ -z "$SYSLOG_SERVER_ENABLED" ] || [[ "$SYSLOG_SERVER_ENABLED" =~ [Nn][Oo] ]] || [[ "$SYSLOG_SERVER_ENABLED" =~ [Oo][Ff][Ff] ]] || [[ "$SYSLOG_SERVER_ENABLED" =~ [Ff][Aa][Ll][Ss][Ee] ]]
then
  sync
  [ -f "${0}" ] && rm -- "${0}"
  exit 0
fi

# RFC 5424 logging from remote clients
tee -a /etc/syslog-ng/syslog-ng.conf <<EOF

source s_prov_remote {
  syslog(ip("${SYSLOG_BIND_IP}") port(${SYSLOG_BIND_PORT}));
};

destination d_prov_remote {
  file("${SYSLOG_LOGFILE}");
};

log {
  source(s_prov_remote);
  destination(d_prov_remote);
};
EOF

ufw disable
if [ -z "${SYSLOG_BIND_IP}" ] || [ "0.0.0.0" = "${SYSLOG_BIND_IP}" ] || [ "::" = "${SYSLOG_BIND_IP}" ]; then
  SYSLOG_BIND_IP="any"
fi
ufw allow from any to ${SYSLOG_BIND_IP} proto tcp port ${SYSLOG_BIND_PORT} comment 'allow rfc 5424 logserver'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
