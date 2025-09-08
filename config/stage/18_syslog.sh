#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

SYSLOG_ENABLED="$(yq -r '.setup.remote_log.enabled' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_SERVER="$(yq -r '.setup.remote_log.syslog_server' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_PORT="$(yq -r '.setup.remote_log.syslog_port' /var/lib/cloud/instance/config/setup.yml)"

if [ -z "$SYSLOG_ENABLED" ] || [[ "$SYSLOG_ENABLED" =~ [Nn][Oo] ]] || [[ "$SYSLOG_ENABLED" =~ [Oo][Ff][Ff] ]] || [[ "$SYSLOG_ENABLED" =~ [Ff][Aa][Ll][Ss][Ee] ]]
then
  sync
  [ -f "${0}" ] && rm -- "${0}"
  exit 0
fi

# enable remote logging
tee -a /etc/syslog-ng/syslog-ng.conf <<EOF

destination d_prov_net {
  syslog("${SYSLOG_SERVER}" port(${SYSLOG_PORT}));
};

log {
  source(s_prov_system);
  filter(f_prov_system);
  destination(d_prov_net);
};
EOF

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
