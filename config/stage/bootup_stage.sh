#cloud-boothook
#!/usr/bin/sh

# improve boot time by not waiting for ntp
systemctl stop systemd-time-wait-sync.service
systemctl disable systemd-time-wait-sync.service
systemctl mask time-sync.target

# sync everything to disk
sync

# cleanup
rm -- "${0}"
