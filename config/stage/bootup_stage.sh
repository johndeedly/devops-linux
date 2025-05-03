#cloud-boothook
#!/usr/bin/sh

# improve boot time by not waiting for ntp
systemctl stop systemd-time-wait-sync.service
systemctl disable systemd-time-wait-sync.service
systemctl mask time-sync.target

# create a 2GiB swap file
# https://btrfs.readthedocs.io/en/latest/Swapfile.html
truncate -s 0 /swapfile
chattr +C /swapfile
fallocate -l 2G /swapfile
chmod 0600 /swapfile
mkswap /swapfile
swapon /swapfile
tee /etc/fstab <<EOF
/swapfile        none        swap        defaults      0 0
EOF
systemctl daemon-reload

# sync everything to disk
sync

# cleanup
rm -- "${0}"
