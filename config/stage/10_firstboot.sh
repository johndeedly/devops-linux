#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# load the keyboard layout for the current session
if [ -f /usr/lib/systemd/systemd-vconsole-setup ]; then
  /usr/lib/systemd/systemd-vconsole-setup
fi

# import cloud-init logs
tee -a /cidata_log <<<":: import cloud-init logs up to this point in time" >/dev/null
sed -e '/DEBUG/d' /var/log/cloud-init.log | tee -a /cidata_log >/dev/null

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
    # deb.debian.org is unreliable
    sed -e 's|http://|https://|g' -e 's|deb[.]debian[.]org|eu.mirror.ionos.com/linux/distributions/debian|g' -i /etc/apt/mirrors/debian.list
    sed -e 's|http://|https://|g' -e 's|deb[.]debian[.]org|eu.mirror.ionos.com/linux/distributions/debian|g' -i /etc/apt/mirrors/debian-security.list
  elif grep -q Ubuntu /proc/version; then
    # old format
    sed -i 's/\(deb .* main\).*/\1 universe restricted multiverse/' /etc/apt/sources.list
    sed -i 's/\(deb .* main\).*/\1 universe restricted multiverse/' /etc/apt/sources.list.d/ubuntu.sources
    # new format
    sed -i 's/\(Comp.* main\).*/\1 universe restricted multiverse/' /etc/apt/sources.list
    sed -i 's/\(Comp.* main\).*/\1 universe restricted multiverse/' /etc/apt/sources.list.d/ubuntu.sources
    # archive.ubuntu.com is unreliable
    sed -e 's|http://|https://|g' -e 's|archive[.]ubuntu[.]com|eu.mirror.ionos.com/linux/distributions/ubuntu|g' -i /etc/apt/sources.list
    sed -e 's|http://|https://|g' -e 's|archive[.]ubuntu[.]com|eu.mirror.ionos.com/linux/distributions/ubuntu|g' -i /etc/apt/sources.list.d/ubuntu.sources
    sed -e 's|http://|https://|g' -e 's|security[.]ubuntu[.]com|eu.mirror.ionos.com/linux/distributions/ubuntu|g' -i /etc/apt/sources.list
    sed -e 's|http://|https://|g' -e 's|security[.]ubuntu[.]com|eu.mirror.ionos.com/linux/distributions/ubuntu|g' -i /etc/apt/sources.list.d/ubuntu.sources
  fi
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt update
fi

# enable multilib
if [ -e /bin/pacman ]; then
  sed -i '/^#\[multilib\]/,/^$/ s/^#//g' /etc/pacman.conf
fi

# speedup apt on ubuntu and debian
if [ -e /bin/apt ]; then
  APT_CFGS=( /etc/apt/apt.conf.d/* )
  for cfg in "${APT_CFGS[@]}"; do
    sed -i 's/^Acquire::http::Dl-Limit/\/\/Acquire::http::Dl-Limit/' "$cfg" || true
  done
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y install eatmydata
fi

# full system upgrade
if [ -e /bin/apt ]; then
  if grep -q Ubuntu /proc/version; then
    # switch from linux-virtual to linux-generic
    LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y install linux-generic
    # install current kernel modules before full system upgrade
    LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y install linux-modules-$(uname -r) linux-modules-extra-$(uname -r)
    ls -1 /lib/modules | while read -r line; do
      depmod -a "$line"
    done
    LC_ALL=C DEBIAN_FRONTEND=noninteractive update-initramfs -u
    update-grub
  fi
  # backup modules of running kernel
  ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -cf /kernel-modules-backup.tar.zst "/lib/modules/$(uname -r)/" &>/dev/null
  echo -n "Kernel modules backup ($(uname -r)): "
  stat -c "%n, %s bytes" /kernel-modules-backup.tar.zst
  # upgrade now
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
elif [ -e /bin/pacman ]; then
  # backup modules of running kernel
  ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -cf /kernel-modules-backup.tar.zst "/lib/modules/$(uname -r)/" &>/dev/null
  echo -n "Kernel modules backup ($(uname -r)): "
  stat -c "%n, %s bytes" /kernel-modules-backup.tar.zst
  # upgrade now
  LC_ALL=C yes | LC_ALL=C pacman -Syu --needed --noconfirm
elif [ -e /bin/yum ]; then
  # install current kernel modules before full system upgrade
  LC_ALL=C yes | LC_ALL=C dnf install -y kernel-modules-$(uname -r) kernel-modules-core-$(uname -r) kernel-modules-extra-$(uname -r)
  ls -1 /lib/modules | while read -r line; do
    depmod -a "$line"
  done
  # backup modules of running kernel
  ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -cf /kernel-modules-backup.tar.zst "/lib/modules/$(uname -r)/" &>/dev/null
  echo -n "Kernel modules backup ($(uname -r)): "
  stat -c "%n, %s bytes" /kernel-modules-backup.tar.zst
  # upgrade now
  LC_ALL=C yes | LC_ALL=C dnf install -y epel-release
  LC_ALL=C yes | LC_ALL=C dnf config-manager --enable crb
  LC_ALL=C yes | LC_ALL=C dnf upgrade -y
  LC_ALL=C yes | LC_ALL=C yum check-update
  LC_ALL=C yes | LC_ALL=C yum update -y
fi

# restore (still running) kernel modules
ZSTD_CLEVEL=4 ZSTD_NBTHREADS=4 tar -I zstd -xkf /kernel-modules-backup.tar.zst &>/dev/null
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

# disable hibernation and hybrid-sleep modes
cp /etc/systemd/logind.conf /etc/systemd/logind.conf.bak
sed -i 's/^#\?HandlePowerKey=.*/HandlePowerKey=poweroff/' /etc/systemd/logind.conf
sed -i 's/^#\?HandlePowerKeyLongPress=.*/HandlePowerKeyLongPress=poweroff/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleRebootKey=.*/HandleRebootKey=reboot/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleRebootKeyLongPress=.*/HandleRebootKeyLongPress=poweroff/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleSuspendKey=.*/HandleSuspendKey=suspend/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleSuspendKeyLongPress=.*/HandleSuspendKeyLongPress=poweroff/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleHibernateKey=.*/HandleHibernateKey=suspend/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleHibernateKeyLongPress=.*/HandleHibernateKeyLongPress=poweroff/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=suspend/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf
sed -i 's/^#\?HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
cp /etc/systemd/sleep.conf /etc/systemd/sleep.conf.bak
sed -i 's/^#\?AllowSuspend=.*/AllowSuspend=yes/' /etc/systemd/sleep.conf
sed -i 's/^#\?AllowHibernation=.*/AllowHibernation=no/' /etc/systemd/sleep.conf
sed -i 's/^#\?AllowSuspendThenHibernate=.*/AllowSuspendThenHibernate=no/' /etc/systemd/sleep.conf
sed -i 's/^#\?AllowHybridSleep=.*/AllowHybridSleep=no/' /etc/systemd/sleep.conf
systemctl mask hibernate.target suspend-then-hibernate.target hybrid-sleep.target

# create user homes on login
# see https://wiki.archlinux.org/title/LDAP_authentication for more details
# TODO: on ubuntu system-login is missing - investigate!
if [ -f /etc/pam.d/system-login ]; then
    sed -i 's/^\(session.*pam_env.so\)/\1\nsession    required   pam_mkhomedir.so     skel=\/etc\/skel umask=0077/' /etc/pam.d/system-login
fi

# enable ntfs3 kernel support for read/write/repair of partitions
echo "ntfs3" | tee /etc/modules-load.d/ntfs3.conf
tee /etc/udev/rules.d/50-ntfs.rules <<EOF
SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="ntfs", ENV{ID_FS_TYPE}="ntfs3"
EOF
# enable cifs kernel support for windows shares
echo "cifs" | tee /etc/modules-load.d/cifs.conf
# enable sg kernel support for dvd/bluray drives
echo "sg" | tee /etc/modules-load.d/sg.conf

# user first time login script
tee /usr/local/bin/userlogin.sh <<'EOS'
#!/usr/bin/env bash

# prepare user directory
if [[ ! -f $HOME/.ssh/id_ed25519.pub ]]; then
  echo "Generating ssh keys for user '$USER'."
  mkdir -p $HOME/.ssh
  chmod 0700 $HOME/.ssh
  ssh-keygen -t ed25519 -N "" -C "" -f $HOME/.ssh/id_ed25519
  ssh-keygen -t rsa -N "" -C "" -f $HOME/.ssh/id_rsa
  chmod 0600 $HOME/.ssh/id_ed25519 $HOME/.ssh/id_rsa
  chmod 0644 $HOME/.ssh/id_ed25519.pub $HOME/.ssh/id_rsa.pub
  eval "$(ssh-agent -s)"
  ssh-add $HOME/.ssh/id_ed25519
  ssh-add $HOME/.ssh/id_rsa
  eval "$(ssh-agent -k)"
fi
if [[ ! -f $HOME/.wg/$USER.key ]]; then
  echo "Generating wireguard keys for user '$USER'."
  mkdir -p $HOME/.wg
  chmod 0700 $HOME/.wg
  wg genkey | tee $HOME/.wg/$USER.key | wg pubkey > $HOME/.wg/$USER.pub
  chmod 0600 $HOME/.wg/$USER.key
  chmod 0644 $HOME/.wg/$USER.pub
fi
# prevent error https://github.com/kovidgoyal/kitty/issues/320
# open terminal failed: missing or unsuitable terminal: xterm-kitty
tee $HOME/.ssh/config <<EOX
SetEnv TERM=screen
EOX
# force update font cache on first login
fc-cache -fv
EOS
chmod +x /usr/local/bin/userlogin.sh
tee /etc/systemd/user/userlogin.service <<'EOF'
[Unit]
Description=Execute on first user login after boot
[Service]
Type=simple
StandardInput=null
StandardOutput=journal
StandardError=journal
ExecStart=-/usr/local/bin/userlogin.sh
[Install]
WantedBy=default.target
EOF
systemctl --global enable userlogin.service

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
    jq yq openssh-server openssh-client systemd-container unattended-upgrades ufw xkcdpass cryptsetup \
    syslog-ng logrotate libxml2 man manpages-de wireguard-tools python3-pip python3-venv \
    gvfs gvfs-backends cifs-utils tmux \
    build-essential npm fd-find neovim
  systemctl enable ssh ufw syslog-ng logrotate.timer
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install systemd-homed \
    bash-completion ncdu pv mc ranger fzf moreutils htop btop git \
    lshw zstd unzip p7zip rsync xdg-user-dirs xdg-utils util-linux snapper
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive dpkg-reconfigure --frontend=noninteractive unattended-upgrades
  systemctl enable systemd-networkd systemd-resolved systemd-homed
  systemctl disable NetworkManager NetworkManager-wait-online NetworkManager-dispatcher || true
  systemctl mask NetworkManager NetworkManager-wait-online NetworkManager-dispatcher
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed kernel-modules-hook polkit curl wget nano jq yq openssh ufw xkcdpass cryptsetup
  systemctl enable linux-modules-cleanup sshd ufw
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed \
    bash-completion ncdu viu pv mc ranger fzf moreutils htop btop git lazygit \
    lshw zstd unzip p7zip rsync xdg-user-dirs xdg-utils util-linux snapper \
    pacman-contrib syslog-ng logrotate libxml2 core/man man-pages-de wireguard-tools python-pip \
    gvfs gvfs-smb cifs-utils tmux \
    base-devel npm fd neovim
  systemctl enable systemd-networkd systemd-resolved systemd-homed syslog-ng@default logrotate.timer
  systemctl disable NetworkManager NetworkManager-wait-online NetworkManager-dispatcher || true
  systemctl mask NetworkManager NetworkManager-wait-online NetworkManager-dispatcher
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C yum install -y systemd-container polkit curl wget nano jq openssh ufw cryptsetup
  systemctl enable sshd ufw
  download_yq
  LC_ALL=C yes | LC_ALL=C yum install -y systemd-networkd \
    bash-completion ncdu pv mc ranger fzf moreutils htop btop git \
    lshw zstd unzip p7zip rsync xdg-user-dirs xdg-utils util-linux snapper \
    syslog-ng logrotate libxml2 man-db wireguard-toolsgvfs python3-pip \
    gvfs-smb cifs-utils tmux \
    cmake make automake gcc gcc-c++ kernel-devel npm fd-find neovim
  systemctl enable systemd-networkd systemd-resolved syslog-ng logrotate.timer
  systemctl disable NetworkManager NetworkManager-wait-online NetworkManager-dispatcher || true
  systemctl mask NetworkManager NetworkManager-wait-online NetworkManager-dispatcher
fi

# generate random hostname once when no specific hostname is set up
SET_HOSTNAME="$(yq -r '.setup.hostname' /var/lib/cloud/instance/config/setup.yml)"
if [ "x$SET_HOSTNAME" = "x" ]; then
  tee /etc/hostname >/dev/null <<EOF
linux-$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 8).internal
EOF
else
  tee /etc/hostname >/dev/null <<EOF
${SET_HOSTNAME}
EOF
fi
hostnamectl hostname "$(</etc/hostname)"

# configure journald -> forward everything to syslog-ng
mkdir -p /etc/systemd/journald.conf.d
tee /etc/systemd/journald.conf.d/provision.conf <<EOF
[Journal]
# "Storage=none" means the systemd journal will drop all messages
#  -> "ForwardToSyslog=yes" is a must have
# With "Storage=volatile/auto" syslog-ng pulls in the messages from the systemd journal by default
#  -> "ForwardToSyslog=yes" means wasted system resources, duplicate log entries or additional errors
Storage=volatile
ForwardToSyslog=no
EOF

# configure syslog-ng -> log system() and internal() to local files
sed -e '/^log.*};/d' -e '/^log/,/};/d' -e '/^options.*};/d' -e '/^options/,/};/d' -i /etc/syslog-ng/syslog-ng.conf
tee -a /etc/syslog-ng/syslog-ng.conf <<'EOF'

options {
  chain_hostnames(off);
  keep_hostname(yes);
  log_fifo_size(10000);
  create_dirs(no);
  flush_lines(0);
  use_dns(no);
  use_fqdn(no);
  dns_cache(no);
  owner(0);
  group(0);
  perm(0640);
  stats(freq(0));
  bad_hostname("^gconfd$");
};

source s_prov_system {
  system();
  internal();
};

destination d_prov_system {
  file("/var/log/messages");
  file("/var/log/messages-kv.log" template("$ISODATE $HOST $(format-welf --scope all-nv-pairs)\n") frac-digits(3));
};

destination d_prov_auth {
  file("/var/log/auth.log");
};

destination d_prov_kern {
  file("/var/log/kern.log");
};

destination d_prov_user {
  file("/var/log/user.log");
};

filter f_prov_not_debug {
  not level(debug);
};

filter f_prov_system {
  filter(f_prov_not_debug);
};

filter f_prov_auth {
  facility(auth, authpriv) and filter(f_prov_not_debug);
};

filter f_prov_kern {
  facility(kern) and filter(f_prov_not_debug);
};

filter f_prov_user {
  facility(user) and filter(f_prov_not_debug);
};

log {
  source(s_prov_system);
  filter(f_prov_system);
  destination(d_prov_system);
};

log {
  source(s_prov_system);
  filter(f_prov_auth);
  destination(d_prov_auth);
};

log {
  source(s_prov_system);
  filter(f_prov_kern);
  destination(d_prov_kern);
};

log {
  source(s_prov_system);
  filter(f_prov_user);
  destination(d_prov_user);
};
EOF

# configure logrotate
sed -i 's/^include/#include/g' /etc/logrotate.conf
tee -a /etc/logrotate.conf <<'EOF'

# provisioned
/var/log/*.log /var/log/messages {
    missingok
    notifempty
    daily
    rotate 7
    compress
    delaycompress
    maxage 30
    size 100M
    sharedscripts
    postrotate
        /bin/kill -HUP $(cat /run/syslog-ng.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
EOF

# prepare neovim
mkdir -p /etc/skel/.local/share
( trap 'kill -- -$$' EXIT; HOME=/etc/skel /bin/bash -c 'nvim --headless -u "/etc/skel/.config/nvim/init.lua" -c ":qall!" || true' ) &
pid=$!
wait $pid

# enabling btrfs root snapshots when not inside a container
if findmnt -t btrfs -n /; then
  echo "[ OK ] Detected btrfs root, enable daily/weekly/monthly snapshots"
  snapper -c root create-config /
  sed -i 's/TIMELINE_MIN_AGE=.*/TIMELINE_MIN_AGE="1800"/' /etc/snapper/configs/root
  sed -i 's/TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="0"/' /etc/snapper/configs/root
  sed -i 's/TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="2"/' /etc/snapper/configs/root
  sed -i 's/TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="2"/' /etc/snapper/configs/root
  sed -i 's/TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="1"/' /etc/snapper/configs/root
  sed -i 's/TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root
  mkdir -p /etc/systemd/system/snapper-{backup,boot,timeline,cleanup}{.timer.d,.service.d}
  tee /etc/systemd/system/snapper-{backup,boot,timeline,cleanup}{.timer.d,.service.d}/override.conf <<EOF
[Unit]
ConditionVirtualization=
ConditionVirtualization=!container
EOF
  systemctl enable snapper-timeline.timer snapper-cleanup.timer
else
  echo "[FAIL] No btrfs root detected, no snapshots will be available"
  systemctl disable snapper-timeline.timer snapper-cleanup.timer
fi

# enabling ufw filters
modprobe iptable_filter
modprobe ip6table_filter
modprobe xt_multiport
# configure ufw
ufw disable
# clear default ruleset
LC_ALL=C yes | LC_ALL=C ufw reset
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
# ssh access on all devices
ufw allow log ssh comment 'allow ssh'
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

# assign a sub uid and gid range to each possible (wanted) user
idcounter=$((100000))
idnum=$((65536))
( echo 0; seq 1000 65535 ) | while read -r line; do
  echo "${line}:${idcounter}:${idnum}"
  idcounter=$((idcounter + idnum))
done | tee /etc/subuid /etc/subgid >/dev/null

# enable mDNS
systemctl stop avahi-daemon{.service,.socket}
systemctl disable avahi-daemon{.service,.socket}
systemctl mask avahi-daemon{.service,.socket}
sed -e 's/^#\?MulticastDNS.*/MulticastDNS=yes/' -e 's/^#\?LLMNR.*/LLMNR=no/' -i /etc/systemd/resolved.conf
[ -d /etc/NetworkManager/conf.d ] && tee -a /etc/NetworkManager/conf.d/globals.conf <<EOF
[connection]
connection.mdns=2
connection.llmnr=0
[main]
dns=none
rc-manager=unmanaged
EOF
# debian 13 hack
mkdir -p /etc/systemd/resolved.conf.d
ln -s /dev/null /etc/systemd/resolved.conf.d/00-disable-mdns.conf

# open firewall for mdns
ufw disable
ufw allow mdns comment 'allow mdns'
ufw enable
ufw status verbose

# enable default mDNS advertising
mkdir -p /etc/systemd/dnssd
tee /etc/systemd/dnssd/ssh.dnssd <<EOF
[Service]
Name=%H
Type=_ssh._tcp
Port=22
EOF
tee /etc/systemd/dnssd/cockpit.dnssd <<EOF
[Service]
Name=%H
Type=_cockpit._tcp
Port=9090
EOF

# disable UPnP (keeping the rules for mDNS)
ufw disable
sed -i 's/^\(.*--dport 1900.*\)/#\1/' /etc/ufw/before.rules
sed -i 's/^\(.*--dport 1900.*\)/#\1/' /etc/ufw/before6.rules
ufw enable

# apply skeleton to all users
getent passwd | while IFS=: read -r username x uid gid gecos home shell; do
  if [ -n "$home" ] && [ -d "$home" ] && [ "$home" != "/" ]; then
    if [ "$uid" -eq 0 ] || [ "$uid" -ge 1000 ]; then
      echo ":: apply skeleton to $home [$username $uid:$gid]"
      rsync -a --chown=$uid:$gid /etc/skel/ "$home"
    fi
  fi
done

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
