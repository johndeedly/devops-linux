#cloud-boothook
#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# stop and disable reflector to be able to change the pacman mirrorlist
# run pacman init when everything is ready
systemctl stop reflector.service reflector.timer pacman-init.service
systemctl disable reflector.service reflector.timer pacman-init.service
systemctl mask reflector.service reflector.timer

# improve boot time by not waiting for ntp
systemctl stop systemd-time-wait-sync.service
systemctl disable systemd-time-wait-sync.service
systemctl mask time-sync.target

# sync everything to disk
sync

# cleanup
rm -- "${0}"
