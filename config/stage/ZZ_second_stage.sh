#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# activate second stage
find /var/lib/cloud/scripts/per-boot -name '*.sh' -exec chmod 0755 {} \;

# sync everything to disk
sync

# cleanup
rm -- "${0}"
