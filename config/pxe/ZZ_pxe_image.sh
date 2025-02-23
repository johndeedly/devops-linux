#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# disable systemd-network-generator in pxe image
systemctl mask systemd-network-generator

# create a squashfs snapshot based on rootfs
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install squashfs-tools
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed squashfs-tools
fi
if [ -e /bin/apt ]; then
  mkdir -p /srv/pxe/debian/x86_64
  sync
  mksquashfs / /srv/pxe/debian/x86_64/pxeboot.img -comp zstd -Xcompression-level 4 -b 1M -progress -wildcards \
    -e "boot/*" "cidata*" "dev/*" "etc/fstab*" "etc/crypttab*" "proc/*" "sys/*" "run/*" "mnt/*" "share/*" "srv/pxe/*" "media/*" "tmp/*" "var/tmp/*" "var/log/*" "var/cache/apt/*"
elif [ -e /bin/pacman ]; then
  mkdir -p /srv/pxe/arch/x86_64
  sync
  mksquashfs / /srv/pxe/arch/x86_64/pxeboot.img -comp zstd -Xcompression-level 4 -b 1M -progress -wildcards \
    -e "boot/*" "cidata*" "dev/*" "etc/fstab*" "etc/crypttab*" "proc/*" "sys/*" "run/*" "mnt/*" "share/*" "srv/pxe/*" "media/*" "tmp/*" "var/tmp/*" "var/log/*" "var/cache/pacman/pkg/*"
fi

# reenable systemd-network-generator
systemctl unmask systemd-network-generator

if [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed mkinitcpio-nfs-utils curl ca-certificates-utils cifs-utils nfs-utils nbd open-iscsi nvme-cli
fi

# configuring iscsi
sed -e 's/^node.conn[0].timeo.noop_out_interval.*/node.conn[0].timeo.noop_out_interval = 0/' \
    -e 's/^node.conn[0].timeo.noop_out_timeout.*/node.conn[0].timeo.noop_out_timeout = 0/' \
    -e 's/^node.session.timeo.replacement_timeout.*/node.session.timeo.replacement_timeout = 86400/' -i /etc/iscsi/iscsid.conf
tee /etc/udev/rules.d/50-iscsi.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="scsi" , ATTR{type}=="0|7|14", RUN+="/bin/sh -c 'echo Y > /sys$$DEVPATH/timeout'"
EOF

if [ -e /bin/pacman ]; then
  echo ":: create skeleton for pxe boot mkinitcpio"
  mkdir -p /etc/initcpio/{install,hooks}
  cp /var/lib/cloud/instance/provision/pxe/install/* /etc/initcpio/install/
  chmod a+x /etc/initcpio/install/*
  cp /var/lib/cloud/instance/provision/pxe/hooks/* /etc/initcpio/hooks/
  chmod a+x /etc/initcpio/hooks/*
  mkdir -p /etc/mkinitcpio{,.conf}.d
  cp /var/lib/cloud/instance/provision/pxe/pxe.conf /etc/
  cp /var/lib/cloud/instance/provision/pxe/pxe.preset /etc/mkinitcpio.d/

  echo ":: create pxe boot initcpio"
  mkdir -p /var/tmp/mkinitcpio
  mkinitcpio -p pxe -t /var/tmp/mkinitcpio
  cp /boot/vmlinuz-linux /boot/initramfs-linux-pxe.img /srv/pxe/arch/x86_64/
  chmod 644 /srv/pxe/arch/x86_64/*
  chown root:root /srv/pxe/arch/x86_64/*
fi

# sync everything to disk
sync

# cleanup
rm -- "${0}"
