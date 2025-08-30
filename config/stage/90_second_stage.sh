#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# move second stage
FILELIST=$(find /var/lib/cloud/instance/second-stage -name '*.sh')
if [ -n "$FILELIST" ]; then
  mkdir -p /var/lib/cloud/scripts/per-boot
  sort <<<"$FILELIST" | while read -r line; do
    mv "$line" /var/lib/cloud/scripts/per-boot/
  done
fi

# activate second stage
FILELIST=$(find /var/lib/cloud/scripts/per-boot -name '*.sh')
if [ -n "$FILELIST" ]; then
  echo ":: Enable second stage"
  sort <<<"$FILELIST" | while read -r line; do
    echo "-> $line"
    chmod 0755 "$line"
  done
fi

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
