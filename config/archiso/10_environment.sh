#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# load the keyboard layout for the current session
/usr/lib/systemd/systemd-vconsole-setup

# import cloud-init logs
tee -a /cidata_log <<<":: import cloud-init logs up to this point in time" >/dev/null
sed -e '/DEBUG/d' /var/log/cloud-init.log | tee -a /cidata_log >/dev/null

# allocate more space for copy on write area
if [ -e /run/archiso/cowspace ]; then
    mount -o remount,size=75% /run/archiso/cowspace || true
fi

# Make the journal log persistent in ramfs
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
systemctl restart systemd-journald

# wait online
echo ":: wait for any interface to be online"
/usr/lib/systemd/systemd-networkd-wait-online --operational-state=routable --any

# locate the cidata iso and mount it to /iso
CIDATA_DEVICE=$(lsblk -no PATH,LABEL,FSTYPE | sed -e '/cidata/I!d' -e '/iso9660/I!d' | head -n1 | cut -d' ' -f1)
test -n "$CIDATA_DEVICE" && mount -o X-mount.mkdir "$CIDATA_DEVICE" /iso
mountpoint -q /iso || ( test -f /cidata/meta-data && mount --bind -o X-mount.mkdir /cidata /iso )

# sync everything to disk
sync

# cleanup
rm -- "${0}"
