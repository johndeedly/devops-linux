#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# activate second stage
find /var/lib/cloud/scripts/per-boot -name '*.sh' -exec chmod 0755 {} \;

# sync everything to disk
sync

# reboot the system if packer is not controlling the provision process
if ! pstree -ps $$ | grep -q 'sshd'; then
  ( (
    sleep 5
    # valid exit codes are 0 or 2
    cloud-init status --wait >/dev/null 2>&1 || true
    echo "[ OK ] Rebooting the system"
    reboot now
  ) & )
  # double fork trick to prevent the subprocess from exiting
fi

# cleanup
rm -- "${0}"
