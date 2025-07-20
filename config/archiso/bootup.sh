#cloud-boothook
#!/usr/bin/env bash

# stop and disable reflector to be able to change the pacman mirrorlist
# run pacman init when everything is ready
if [ -f /usr/lib/systemd/system/reflector.service ]; then
  systemctl stop reflector.service reflector.timer pacman-init.service
  systemctl disable reflector.service reflector.timer pacman-init.service
  systemctl mask reflector.service reflector.timer
fi

# improve boot time by not waiting for ntp
systemctl stop systemd-time-wait-sync.service
systemctl disable systemd-time-wait-sync.service
systemctl mask time-sync.target

# generate random hostname
tee /etc/hostname >/dev/null <<EOF
linux-$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 8)-setup.internal
EOF
hostnamectl hostname "$(</etc/hostname)"

# create cidata log
touch /cidata_log

# sync everything to disk
sync

# cleanup
rm -- "${0}"
