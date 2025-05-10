#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# deactivate cloud-init on startup
find /etc/systemd -type d -name 'cloud-init.target*' | while read -r line; do
  echo "[ ## ] deactivate cloud-init on startup: ${line}" && rm -r "${line}"
done
echo "[ ## ] remove cloud-init datasource: /cidata" && rm -r /cidata

# sync everything to disk
sync

# cleanup
rm -- "${0}"
