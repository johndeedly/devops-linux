#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

SYSLOG_ENABLED="$(yq -r '.setup.remote_log.enabled' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_SERVER="$(yq -r '.setup.remote_log.syslog_server' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_PORT="$(yq -r '.setup.remote_log.syslog_port' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_X509_KEY="$(yq -r '.setup.remote_log.x509_key' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_X509_CRT="$(yq -r '.setup.remote_log.x509_crt' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_X509_HASH="$(yq -r '.setup.remote_log.x509_hash' /var/lib/cloud/instance/config/setup.yml)"
SYSLOG_PEER_VERIFY="$(yq -r '.setup.remote_log.peer_verify' /var/lib/cloud/instance/config/setup.yml)"

if [ -z "$SYSLOG_ENABLED" ] || [[ "$SYSLOG_ENABLED" =~ [Nn][Oo] ]] || [[ "$SYSLOG_ENABLED" =~ [Oo][Ff][Ff] ]] || [[ "$SYSLOG_ENABLED" =~ [Ff][Aa][Ll][Ss][Ee] ]]
then
  sync
  [ -f "${0}" ] && rm -- "${0}"
  exit 0
fi

if [ -n "${SYSLOG_X509_KEY}" ] && [ -n "${SYSLOG_X509_CRT}" ]; then
  mkdir -p /etc/syslog-ng/cert.d
  tee /etc/syslog-ng/cert.d/client.key <<EOF
${SYSLOG_X509_KEY}
EOF
  tee /etc/syslog-ng/cert.d/client.crt <<EOF
${SYSLOG_X509_CRT}
EOF
  chmod 0700 /etc/syslog-ng/cert.d
  chmod 0600 /etc/syslog-ng/cert.d/client.{key,crt}
fi

# enable RFC 5424 logging
if [ -n "${SYSLOG_X509_KEY}" ] && [ -n "${SYSLOG_X509_CRT}" ]; then
  tee -a /etc/syslog-ng/syslog-ng.conf <<EOF

destination d_prov_net {
  syslog("${SYSLOG_SERVER}" port(${SYSLOG_PORT}) transport(tls) tls(
    peer-verify(${SYSLOG_PEER_VERIFY})
    trusted-keys("${SYSLOG_X509_HASH}")
    key-file("/etc/syslog-ng/cert.d/client.key")
    cert-file("/etc/syslog-ng/cert.d/client.crt")
  ));
};

log {
  source(s_prov_system);
  filter(f_prov_system);
  destination(d_prov_net);
};
EOF
else
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
fi

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
