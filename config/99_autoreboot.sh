#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# double fork trick to prevent the subprocess from exiting
echo "[ ## ] Wait for cloud-init to finish"
( (
  # valid exit codes are 0 or 2
  cloud-init status --long --format yaml --wait | sed -e 's/^/>>> /g'
  ret=$?
  if [ $ret -eq 0 ] || [ $ret -eq 2 ]; then
    echo "[ OK ] Rebooting the system"
    reboot now
  else
    echo "[ FAILED ] Unrecoverable error in provision steps"
  fi
) & )

# cleanup
[ -f "${0}" ] && rm -- "${0}"
