#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# load the keyboard layout for the current session
if [ -f /usr/lib/systemd/systemd-vconsole-setup ]; then
  /usr/lib/systemd/systemd-vconsole-setup
fi

# import cloud-init logs
tee -a /cidata_log <<<":: import cloud-init logs up to this point in time" >/dev/null
sed -e '/DEBUG/d' /var/log/cloud-init.log | tee -a /cidata_log >/dev/null

# generate random hostname once
tee /etc/hostname >/dev/null <<EOF
linux-$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 8).internal
EOF
hostnamectl hostname "$(</etc/hostname)"

# Make the journal log persistent when folder structure is present
# and forward everything to rsyslog
mkdir -p /var/log/journal /etc/systemd/journald.conf.d
systemd-tmpfiles --create --prefix /var/log/journal
tee /etc/systemd/journald.conf.d/provision.conf <<EOF
[Journal]
Storage=auto
ForwardToSyslog=yes
EOF
systemctl restart systemd-journald

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
    # archive.ubuntu.com is unreliable
    sed -i 's|archive[.]ubuntu[.]com|de.archive.ubuntu.com|g' /etc/apt/sources.list
    sed -i 's|archive[.]ubuntu[.]com|de.archive.ubuntu.com|g' /etc/apt/sources.list.d/ubuntu.sources
    sed -i 's|security[.]ubuntu[.]com|de.archive.ubuntu.com|g' /etc/apt/sources.list
    sed -i 's|security[.]ubuntu[.]com|de.archive.ubuntu.com|g' /etc/apt/sources.list.d/ubuntu.sources
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

# backup modules of running kernel
ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -cf /kernel-modules-backup.tar.zst "/lib/modules/$(uname -r)/" &>/dev/null
echo -n "Kernel modules backup ($(uname -r)): "
stat -c "%n, %s bytes" /kernel-modules-backup.tar.zst

# full system upgrade
if [ -e /bin/apt ]; then
  if grep -q Ubuntu /proc/version; then
    # switch from linux-virtual to linux-generic
    LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y install linux-generic
    ls -1 /lib/modules | while read -r line; do
      depmod -a "$line"
    done
    LC_ALL=C DEBIAN_FRONTEND=noninteractive update-initramfs -u
    update-grub
  fi
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -Syu --needed --noconfirm
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C dnf install -y epel-release
  LC_ALL=C yes | LC_ALL=C dnf config-manager --enable crb
  LC_ALL=C yes | LC_ALL=C dnf upgrade -y
  LC_ALL=C yes | LC_ALL=C yum check-update
  LC_ALL=C yes | LC_ALL=C yum update -y
fi

# restore (still running) kernel modules
tar -I zstd -xkf /kernel-modules-backup.tar.zst &>/dev/null
rm /kernel-modules-backup.tar.zst

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
  if [ -e /usr/share/zoneinfo/CET ]; then
    ln -s /usr/share/zoneinfo/CET /etc/localtime
  else
    ln -s /usr/share/zoneinfo/Europe/Brussels /etc/localtime
  fi
  dpkg-reconfigure --frontend=noninteractive tzdata
elif [ -e /bin/pacman ]; then
  rm /etc/localtime || true
  if [ -e /usr/share/zoneinfo/CET ]; then
    ln -s /usr/share/zoneinfo/CET /etc/localtime
  else
    ln -s /usr/share/zoneinfo/Europe/Brussels /etc/localtime
  fi
elif [ -e /bin/yum ]; then
  rm /etc/localtime || true
  if [ -e /usr/share/zoneinfo/CET ]; then
    ln -s /usr/share/zoneinfo/CET /etc/localtime
  else
    ln -s /usr/share/zoneinfo/Europe/Brussels /etc/localtime
  fi
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
      LC_ALL=C yes | LC_ALL=C pacman -S --needed --noconfirm qemu-guest-agent
      ;;
    oracle)
      LC_ALL=C yes | LC_ALL=C pacman -S --needed --noconfirm virtualbox-guest-utils
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
GRUB_GLOBAL_CMDLINE="console=tty1 rw loglevel=3 acpi=force acpi_osi=Linux"
GRUB_CFGS=( /etc/default/grub /etc/default/grub.d/* )
for cfg in "${GRUB_CFGS[@]}"; do
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=/#GRUB_CMDLINE_LINUX_DEFAULT=/' "$cfg" || true
  sed -i 's/^GRUB_CMDLINE_LINUX=/#GRUB_CMDLINE_LINUX=/' "$cfg" || true
  sed -i 's/^GRUB_TERMINAL=/#GRUB_TERMINAL=/' "$cfg" || true
  sed -i 's/^GRUB_GFXMODE=/#GRUB_GFXMODE=/' "$cfg" || true
  sed -i 's/^GRUB_GFXPAYLOAD_LINUX=/#GRUB_GFXPAYLOAD_LINUX=/' "$cfg" || true
done
tee -a /etc/default/grub <<EOF

# provisioned
GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_GLOBAL_CMDLINE}"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL=console
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
EOF
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

# configure chaotic keyring
if [ -e /bin/pacman ]; then
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
fi

download_yq() {
  echo ":: download yq"
  curl --fail --silent --location --output /tmp/yq_linux_amd64.tar.gz 'https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64.tar.gz'
  tar -xzof /tmp/yq_linux_amd64.tar.gz -C /usr/local/bin/
  mv /usr/local/bin/yq_linux_amd64 /usr/local/bin/yq
  chmod 0755 /usr/local/bin/yq
}

# very essential programs
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install polkitd curl wget nano \
    jq yq openssh-server openssh-client systemd-container unattended-upgrades ufw xkcdpass cryptsetup
  systemctl enable ssh ufw
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --frontend=noninteractive unattended-upgrades
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed polkit curl wget nano jq yq openssh ufw xkcdpass cryptsetup
  systemctl enable sshd ufw
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C yum install -y systemd-container polkit curl wget nano jq openssh ufw cryptsetup
  systemctl enable sshd ufw
  download_yq
fi

# enabling ufw filters
modprobe iptable_filter
modprobe ip6table_filter
# configure ufw
ufw disable
# clear default ruleset
ufw reset
for i in $(seq -- 10 -1 1)
do
  LC_ALL=C yes | LC_ALL=C ufw delete "$i" 2>/dev/null
done
# logs all blocked packets and packets matching logged rules
ufw logging low
# outgoing is always allowed, incoming and routed should be denied
ufw default deny incoming
ufw default deny routed
ufw default allow outgoing
# limited ssh access on all devices
ufw limit log ssh comment 'allow rate limited ssh'
ufw enable

# enable cockpit
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install cockpit sscg cockpit-storaged cockpit-packagekit
  systemctl enable cockpit.socket
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm cockpit sscg cockpit-storaged cockpit-packagekit
  systemctl enable cockpit.socket
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C yum install -y cockpit sscg cockpit-storaged cockpit-packagekit
  systemctl enable cockpit.socket
fi
ufw disable
ufw allow log 9090/tcp comment 'allow cockpit'
ufw enable
ufw status verbose
ln -sfn /dev/null /etc/motd.d/cockpit
ln -sfn /dev/null /etc/issue.d/cockpit.issue
sed -i '/^root$/d' /etc/cockpit/disallowed-users

# assign a sub uid and gid range to each possible (wanted) user
idcounter=$((100000))
idnum=$((65536))
( echo 0; seq 1000 65535 ) | while read -r line; do
  echo "${line}:${idcounter}:${idnum}"
  idcounter=$((idcounter + idnum))
done | tee /etc/subuid /etc/subgid >/dev/null

# sync everything to disk
sync

# cleanup
rm -- "${0}"
