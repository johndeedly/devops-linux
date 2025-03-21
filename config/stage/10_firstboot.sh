#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# load the keyboard layout for the current session
if [ -f /usr/lib/systemd/systemd-vconsole-setup ]; then
  /usr/lib/systemd/systemd-vconsole-setup
fi

# import cloud-init logs
tee -a /cidata_log <<<":: import cloud-init logs up to this point in time" >/dev/null
sed -e '/DEBUG/d' /var/log/cloud-init.log | tee -a /cidata_log >/dev/null

# wait online (not on rocky, as rocky does not have wait-online preinstalled)
if [ -f /usr/lib/systemd/systemd-networkd-wait-online ]; then
  echo ":: wait for any interface to be online"
  /usr/lib/systemd/systemd-networkd-wait-online --operational-state=routable --any
fi

# generate random hostname once
tee /etc/hostname >/dev/null <<EOF
linux-$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 8).internal
EOF
hostnamectl hostname "$(</etc/hostname)"

# initialize pacman keyring
if [ -e /bin/pacman ]; then
  sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
  LC_ALL=C yes | LC_ALL=C pacman -Sy --noconfirm archlinux-keyring
fi

# initialize apt sources
if [ -e /bin/apt ]; then
  if grep -q Debian /proc/version; then
    # old format
    sed -i 's/\(deb .* main\).*/\1 contrib non-free non-free-firmware/g' /etc/apt/sources.list
    sed -i 's/\(deb .* main\).*/\1 contrib non-free non-free-firmware/g' /etc/apt/sources.list.d/debian.sources
    # new format
    sed -i 's/\(Comp.* main\).*/\1 contrib non-free non-free-firmware/g' /etc/apt/sources.list
    sed -i 's/\(Comp.* main\).*/\1 contrib non-free non-free-firmware/g' /etc/apt/sources.list.d/debian.sources
  elif grep -q Ubuntu /proc/version; then
    # old format
    sed -i 's/\(deb .* main\).*/\1 universe restricted multiverse/' /etc/apt/sources.list
    sed -i 's/\(deb .* main\).*/\1 universe restricted multiverse/' /etc/apt/sources.list.d/ubuntu.sources
    # new format
    sed -i 's/\(Comp.* main\).*/\1 universe restricted multiverse/' /etc/apt/sources.list
    sed -i 's/\(Comp.* main\).*/\1 universe restricted multiverse/' /etc/apt/sources.list.d/ubuntu.sources
  fi
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt update
fi

# speedup apt on ubuntu and debian
if [ -e /bin/apt ]; then
  APT_CFGS=( /etc/apt/apt.conf.d/* )
  for cfg in "${APT_CFGS[@]}"; do
    sed -i 's/^Acquire::http::Dl-Limit/\/\/Acquire::http::Dl-Limit/' "$cfg" || true
  done
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y install eatmydata
fi

# Configure keyboard and console
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install locales keyboard-configuration console-setup console-data tzdata
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C yum install -y glibc-common glibc-locale-source glibc-langpack-de
fi

# Generate locales
if [ -e /bin/apt ]; then
  if [ -f /etc/locale.gen ]; then
    sed -i 's/^#\? \?de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen
  else
    echo "de_DE.UTF-8 UTF-8" > /etc/locale.gen
  fi
  dpkg-reconfigure --frontend=noninteractive locales
  update-locale LANG=de_DE.UTF-8
elif [ -e /bin/pacman ]; then
  if [ -f /etc/locale.gen ]; then
    sed -i 's/^#\? \?de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen
  else
    echo "de_DE.UTF-8 UTF-8" > /etc/locale.gen
  fi
  echo "LANG=de_DE.UTF-8" > /etc/locale.conf
  locale-gen
elif [ -e /bin/yum ]; then
  if [ -f /etc/locale.gen ]; then
    sed -i 's/^#\? \?de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/' /etc/locale.gen
  else
    echo "de_DE.UTF-8 UTF-8" > /etc/locale.gen
  fi
  echo "LANG=de_DE.UTF-8" > /etc/locale.conf
  localedef -c -i de_DE -f UTF-8 de_DE.UTF-8
fi

# Configure timezone
if [ -e /bin/apt ]; then
  rm /etc/localtime || true
  ln -s /usr/share/zoneinfo/CET /etc/localtime
  dpkg-reconfigure --frontend=noninteractive tzdata
elif [ -e /bin/pacman ]; then
  rm /etc/localtime || true
  ln -s /usr/share/zoneinfo/CET /etc/localtime
elif [ -e /bin/yum ]; then
  rm /etc/localtime || true
  ln -s /usr/share/zoneinfo/CET /etc/localtime
fi

# Configure keyboard and console
if [ -e /bin/apt ]; then
  dpkg-reconfigure --frontend=noninteractive keyboard-configuration
  dpkg-reconfigure --frontend=noninteractive console-setup
  mkdir -p /etc/systemd/system/console-setup.service.d
  tee /etc/systemd/system/console-setup.service.d/override.conf <<EOF
[Service]
ExecStartPost=/bin/setupcon
EOF
elif [ -e /bin/pacman ]; then
  loadkeys de-latin1 || true
elif [ -e /bin/yum ]; then
  loadkeys de-latin1 || true
fi

# Configure (virtual) environment
VIRT_ENV=$(systemd-detect-virt)
if [ -e /bin/apt ]; then
  case $VIRT_ENV in
    qemu | kvm)
      LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install qemu-guest-agent
      ;;
    oracle)
      if grep -q Ubuntu /proc/version; then
        LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install virtualbox-guest-x11
      fi
      ;;
  esac
elif [ -e /bin/pacman ]; then
  case $VIRT_ENV in
    qemu | kvm)
      LC_ALL=C yes | LC_ALL=C pacman -Syu --noconfirm qemu-guest-agent
      ;;
    oracle)
      LC_ALL=C yes | LC_ALL=C pacman -Syu --noconfirm virtualbox-guest-utils
      systemctl enable vboxservice.service
      ;;
  esac
elif [ -e /bin/yum ]; then
  case $VIRT_ENV in
    qemu | kvm)
      LC_ALL=C yes | LC_ALL=C yum install -y qemu-guest-agent
      ;;
  esac
fi

# modify grub
GRUB_GLOBAL_CMDLINE="console=tty1 rw loglevel=3 acpi=force acpi_osi=Linux nvidia_drm.modeset=1"
GRUB_CFGS=( /etc/default/grub /etc/default/grub.d/* )
for cfg in "${GRUB_CFGS[@]}"; do
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="'"$GRUB_GLOBAL_CMDLINE"'"/' "$cfg" || true
  sed -i 's/^GRUB_CMDLINE_LINUX=/#GRUB_CMDLINE_LINUX=/' "$cfg" || true
  sed -i 's/^GRUB_TERMINAL=.*/GRUB_TERMINAL=console/' "$cfg" || true
done
if [ -e /bin/apt ]; then
  grub-mkconfig -o /boot/grub/grub.cfg
  if [ -d /boot/efi/EFI/debian ]; then
    grub-mkconfig -o /boot/efi/EFI/debian/grub.cfg
  elif [ -d /boot/efi/EFI/ubuntu ]; then
    grub-mkconfig -o /boot/efi/EFI/ubuntu/grub.cfg
  fi
elif [ -e /bin/pacman ]; then
  grub-mkconfig -o /boot/grub/grub.cfg
elif [ -e /bin/yum ]; then
  grub2-editenv - set "kernelopts=$GRUB_GLOBAL_CMDLINE"
  if [ -e /sbin/grubby ]; then
    grubby --update-kernel=ALL --args="$GRUB_GLOBAL_CMDLINE"
  fi
  grub2-mkconfig -o /boot/grub2/grub.cfg --update-bls-cmdline
  grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg --update-bls-cmdline
fi

# add modules to initcpio
if [ -f /etc/mkinitcpio.conf ]; then
  sed -i 's/^MODULES=.*/MODULES=(usbhid xhci_hcd vfat)/g' /etc/mkinitcpio.conf
fi

# system upgrade
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --needed --noconfirm jq yq
  # main repo key from website
  LC_ALL=C yes | LC_ALL=C pacman-key --recv-key 3056513887B78AEB --keyserver hkp://keys.gnupg.net
  LC_ALL=C yes | LC_ALL=C pacman-key --lsign-key 3056513887B78AEB
  # garuda build key (remove when problems are fixed by the chaotic-aur team)
  LC_ALL=C yes | LC_ALL=C pacman-key --recv-key 349BC7808577C592 --keyserver hkp://keys.gnupg.net
  LC_ALL=C yes | LC_ALL=C pacman-key --lsign-key 349BC7808577C592
  PKG_MIRROR=$(yq -r '.setup.chaotic_mirror' /var/lib/cloud/instance/config/setup.yml)
  if [ -n "$PKG_MIRROR" ] && [ "false" != "$PKG_MIRROR" ]; then
    tee -a /etc/pacman.conf <<EOF
[chaotic-aur]
${PKG_MIRROR}
EOF
  else
    tee -a /etc/pacman.conf <<'EOF'
[chaotic-aur]
Server = https://cf-builds.garudalinux.org/repos/$repo/$arch
EOF
  fi
  LC_ALL=C yes | LC_ALL=C pacman -Syu --noconfirm chaotic-keyring
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C dnf install -y epel-release
  LC_ALL=C yes | LC_ALL=C dnf config-manager --enable crb
  LC_ALL=C yes | LC_ALL=C dnf upgrade -y
  LC_ALL=C yes | LC_ALL=C yum check-update
  LC_ALL=C yes | LC_ALL=C yum update -y
  LC_ALL=C yes | LC_ALL=C yum install -y systemd-container
fi

# very essential programs
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install polkitd curl wget nano \
    jq yq openssh-server openssh-client systemd-container unattended-upgrades firewalld
  systemctl enable ssh firewalld
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --frontend=noninteractive unattended-upgrades
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed polkit curl wget nano jq yq openssh firewalld
  systemctl enable sshd firewalld
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C yum install -y polkit curl wget nano jq yq openssh firewalld
  systemctl enable sshd firewalld
fi

# enable cockpit
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install cockpit cockpit-storaged cockpit-packagekit \
    libblockdev-btrfs2 libblockdev-crypto2 libblockdev-dm2 libblockdev-fs2 libblockdev-loop2 libblockdev-lvm2 libblockdev-mdraid2 \
    libblockdev-mpath2 libblockdev-nvdimm2 libblockdev-part2 libblockdev-swap2
  systemctl enable cockpit.socket
  firewall-offline-cmd --zone=public --add-port=9090/tcp
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm cockpit cockpit-storaged cockpit-packagekit \
    libblockdev-btrfs libblockdev-crypto libblockdev-dm libblockdev-fs libblockdev-loop libblockdev-lvm libblockdev-mdraid \
    libblockdev-mpath libblockdev-nvdimm libblockdev-nvme libblockdev-part libblockdev-smart libblockdev-swap
  systemctl enable cockpit.socket
  firewall-offline-cmd --zone=public --add-port=9090/tcp
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C yum install -y cockpit cockpit-storaged cockpit-packagekit
  systemctl enable cockpit.socket
  firewall-offline-cmd --zone=public --add-port=9090/tcp
fi
ln -sfn /dev/null /etc/motd.d/cockpit
ln -sfn /dev/null /etc/issue.d/cockpit.issue
sed -i '/^root$/d' /etc/cockpit/disallowed-users

# sync everything to disk
sync

# cleanup
rm -- "${0}"
