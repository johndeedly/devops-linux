#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# load the keyboard layout for the current session
/usr/lib/systemd/systemd-vconsole-setup

# import cloud-init logs
tee -a /cidata_log <<<":: import cloud-init logs up to this point in time" >/dev/null
sed -e '/DEBUG/d' /var/log/cloud-init.log | tee -a /cidata_log >/dev/null

# locate the cidata iso and mount it to /iso
CIDATA_DEVICE=$(lsblk -no PATH,LABEL,FSTYPE | sed -e '/cidata/I!d' -e '/iso9660/I!d' | head -n1 | cut -d' ' -f1)
test -n "$CIDATA_DEVICE" && mount -o X-mount.mkdir "$CIDATA_DEVICE" /iso
mountpoint -q /iso || ( test -f /cidata/meta-data && mount --bind -o X-mount.mkdir /cidata /iso )

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
