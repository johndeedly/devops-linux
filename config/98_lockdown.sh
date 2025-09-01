#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

echo "[ ## ] Remove provisioning key to lock down ssh"
sed -i '/packer-provisioning-key/d' /root/.ssh/authorized_keys

echo "[ ## ] Sync disk contents"
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
