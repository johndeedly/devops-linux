#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# add modules to initcpio
sed -i 's/^MODULES=.*/MODULES=(usbhid xhci_hcd vfat)/g' /etc/mkinitcpio.conf

# system upgrade
if [ -e /bin/apt ]; then
  if grep -q Debian /proc/version; then
    sed -i 's/main/main contrib/g' /etc/apt/sources.list.d/debian.sources
    LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y update
  fi
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install systemd-container
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

download_nerdfont() {
  echo ":: download nerdfont terminus"
  curl --fail --silent --location --output /tmp/terminus.tar.xz 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Terminus.tar.xz'
  curl --fail --silent --location --output /tmp/symbols.tar.xz 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.tar.xz'
  mkdir -p /etc/skel/.local/share/fonts
  tar -xof /tmp/terminus.tar.xz -C /etc/skel/.local/share/fonts/
  tar -xof /tmp/symbols.tar.xz -C /etc/skel/.local/share/fonts/
}

download_starship() {
  echo ":: download starship"
  curl --fail --silent --location --output /tmp/starship-x86_64.tar.gz 'https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-musl.tar.gz'
  curl --fail --silent --location --output /tmp/starship-x86_64.tar.gz.sha256 'https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-musl.tar.gz.sha256'
  newhash=$(sha256sum /tmp/starship-x86_64.tar.gz | cut -d' ' -f1)
  knownhash=$(cat /tmp/starship-x86_64.tar.gz.sha256)
  if [ -n "$newhash" ] && [ "$newhash" == "$knownhash" ]; then
    echo ":: correct hash, extract starship to /usr/local/bin/"
    tar -xzof /tmp/starship-x86_64.tar.gz -C /usr/local/bin/
    chmod 0755 /usr/local/bin/starship
  else
    echo "!! error installing starship: wrong hash. expected: $knownhash, got $newhash"
  fi
}

download_neovim() {
  echo ":: download nvim"
  curl --fail --silent --location --output /tmp/nvim-x86_64.tar.gz 'https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz'
  curl --fail --silent --location --output /tmp/nvim-x86_64.tar.gz.sha256 'https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz.sha256sum'
  newhash=$(sha256sum /tmp/nvim-x86_64.tar.gz | cut -d' ' -f1)
  knownhash=$(cat /tmp/nvim-x86_64.tar.gz.sha256 | cut -d' ' -f1)
  if [ -n "$newhash" ] && [ "$newhash" == "$knownhash" ]; then
    echo ":: correct hash, extract nvim to /usr/local/"
    tar -xzof /tmp/nvim-x86_64.tar.gz -C /usr/local/ --strip-components 1
    chmod 0755 /usr/local/bin/nvim
  else
    echo "!! error installing starship: wrong hash. expected: $knownhash, got $newhash"
  fi
}

download_dotnet_debian() {
  echo ":: download dotnet"
  wget https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
  dpkg -i /tmp/packages-microsoft-prod.deb
  rm /tmp/packages-microsoft-prod.deb
  apt-get update
  apt-get install -y dotnet-runtime
}

download_dotnet_yum() {
  echo ":: download dotnet"
  dnf update
  rpm -Uvh https://packages.microsoft.com/config/centos/9/packages-microsoft-prod.rpm
  dnf install dotnet-runtime
}

# install basic packages
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
    systemd-homed build-essential yq \
    curl wget zstd rsyslog nano npm htop btop git firewalld \
    bash-completion ncdu pv mc ranger fzf moreutils \
    lshw libxml2 jq polkitd man manpages-de trash-cli \
    openssh-server openssh-client wireguard-tools nfs-kernel-server \
    gvfs gvfs-backends cifs-utils unzip p7zip rsync xdg-user-dirs xdg-utils \
    libnss-ldap libpam-ldap ldap-utils nslcd python3-pip python3-venv
  download_nerdfont
  download_starship
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
    luajit libluajit-5.1-dev lua-mpack lua-lpeg libunibilium-dev libmsgpack-dev libtermkey-dev
  download_neovim
  download_dotnet_debian
  systemctl enable systemd-networkd systemd-resolved systemd-homed ssh firewalld nslcd
  systemctl disable NetworkManager NetworkManager-wait-online NetworkManager-dispatcher || true
  systemctl mask NetworkManager NetworkManager-wait-online NetworkManager-dispatcher
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed \
    pacman-contrib starship ttf-terminus-nerd ttf-nerd-fonts-symbols powershell-bin base-devel neovim yq \
    curl wget zstd rsyslog nano npm htop btop git firewalld \
    bash-completion ncdu viu pv mc ranger fzf moreutils dotnet-runtime \
    lshw libxml2 jq polkit core/man man-pages-de trash-cli \
    openssh wireguard-tools nfs-utils \
    gvfs gvfs-smb cifs-utils unzip p7zip rsync xdg-user-dirs xdg-utils \
    openldap nss-pam-ldapd python-pip
  systemctl enable systemd-networkd systemd-resolved systemd-homed sshd firewalld nslcd
  systemctl disable NetworkManager NetworkManager-wait-online NetworkManager-dispatcher || true
  systemctl mask NetworkManager NetworkManager-wait-online NetworkManager-dispatcher
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C yum install -y \
    systemd-networkd cmake make automake gcc gcc-c++ kernel-devel \
    curl wget zstd rsyslog nano npm htop btop git firewalld \
    bash-completion ncdu pv mc ranger fzf moreutils \
    lshw libxml2 jq polkit man-db trash-cli \
    openssh wireguard-tools nfs-utils \
    gvfs gvfs-smb cifs-utils unzip p7zip rsync xdg-user-dirs xdg-utils \
    openldap openldap-clients nss-pam-ldapd python3-pip python3-venv
  download_nerdfont
  download_starship
  LC_ALL=C yes | LC_ALL=C yum install -y \
    compat-lua-libs libtermkey libtree-sitter libvterm luajit luajit2.1-luv msgpack unibilium xsel
  download_neovim
  download_dotnet_yum
  systemctl enable systemd-networkd systemd-resolved sshd firewalld nslcd
  systemctl disable NetworkManager NetworkManager-wait-online NetworkManager-dispatcher || true
  systemctl mask NetworkManager NetworkManager-wait-online NetworkManager-dispatcher
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
echo ":: prepare NvChad environment"
mkdir -p /etc/skel/.local/share
echo ":: setup NvChad environment"
( HOME=/etc/skel /bin/bash -c 'nvim --headless -u "/etc/skel/.config/nvim/init.lua" -c ":Lazy sync | Lazy load all" -c ":MasonInstall beautysh omnisharp netcoredbg pyright debugpy pylint dockerfile-language-server texlab latexindent marksman markdownlint clangd cpplint lua-language-server stylua css-lsp htmlhint html-lsp typescript-language-server deno prettier jsonlint clangd clang-format" -c ":qall!" || true' ) &
pid=$!
echo ":: wait for NvChad to finish"
wait $pid
echo ":: create user homes on login"

# see https://wiki.archlinux.org/title/LDAP_authentication for more details
# TODO: on ubuntu system-login is missing - investigate!
if [ -f /etc/pam.d/system-login ]; then
    sed -i 's/^\(session.*pam_env.so\)/\1\nsession    required   pam_mkhomedir.so     skel=\/etc\/skel umask=0077/' /etc/pam.d/system-login
fi

echo ':: enable optional ldap pam and nss authentication, disabling nss by commenting out connection string'
echo ':: to re-enable nss, provide a valid ldap connection string'
if [ -f /etc/pam.d/system-auth ]; then
    sed -i '0,/^auth/s//auth       sufficient                  pam_ldap.so\nauth/' /etc/pam.d/system-auth
    sed -i '0,/^account/s//account    sufficient                  pam_ldap.so\naccount/' /etc/pam.d/system-auth
    sed -i '0,/^password/s//password   sufficient                  pam_ldap.so\npassword/' /etc/pam.d/system-auth
    sed -i '0,/^session/s//session    optional                    pam_ldap.so\nsession/' /etc/pam.d/system-auth
fi
if [ -f /etc/pam.d/su ]; then
    sed -i '0,/pam_rootok.so/s//pam_rootok.so\nauth            sufficient      pam_ldap.so/' /etc/pam.d/su
    sed -i 's/^\(auth.*pam_unix.so\)/\1 use_first_pass/' /etc/pam.d/su
    sed -i '0,/^account/s//account         sufficient      pam_ldap.so\naccount/' /etc/pam.d/su
    sed -i '0,/^session/s//session         sufficient      pam_ldap.so\nsession/' /etc/pam.d/su
fi
if [ -f /etc/pam.d/su-l ]; then
    sed -i '0,/pam_rootok.so/s//pam_rootok.so\nauth            sufficient      pam_ldap.so/' /etc/pam.d/su-l
    sed -i 's/^\(auth.*pam_unix.so\)/\1 use_first_pass/' /etc/pam.d/su-l
    sed -i '0,/^account/s//account         sufficient      pam_ldap.so\naccount/' /etc/pam.d/su-l
    sed -i '0,/^session/s//session         sufficient      pam_ldap.so\nsession/' /etc/pam.d/su-l
fi
if [ -f /etc/nslcd.conf ]; then
  chmod 0600 /etc/nslcd.conf
  sed -i 's|^uri |uri ldap://0.0.0.0/|' /etc/nslcd.conf
fi
if [ -f /etc/nsswitch.conf ]; then
    sed -i 's/^\(passwd.*\)/\1 ldap/' /etc/nsswitch.conf
    sed -i 's/^\(group.*\)/\1 ldap/' /etc/nsswitch.conf
    sed -i 's/^\(shadow.*\)/\1 ldap/' /etc/nsswitch.conf
fi
if [ -f /etc/pam.d/sudo ]; then
    sed -i 's/^\(auth.*pam_unix.so\)/auth      sufficient    pam_ldap.so\n\1 try_first_pass/' /etc/pam.d/sudo
fi

echo ":: enable ntfs3 kernel support for read/write/repair of partitions"
echo "ntfs3" | tee /etc/modules-load.d/ntfs3.conf
tee /etc/udev/rules.d/50-ntfs.rules <<EOF
SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="ntfs", ENV{ID_FS_TYPE}="ntfs3"
EOF
echo ":: enable cifs kernel support for windows shares"
echo "cifs" | tee /etc/modules-load.d/cifs.conf
echo ":: enable sg kernel support for dvd/bluray drives"
echo "sg" | tee /etc/modules-load.d/sg.conf

echo ":: user first time login script"
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

# graphics driver for amd, intel, nvidia, vmware and virtio-gpu
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
    xserver-xorg-video-ati xserver-xorg-video-amdgpu mesa-vulkan-drivers mesa-vdpau-drivers nvtop \
    xserver-xorg-video-nouveau \
    xserver-xorg-video-intel \
    xserver-xorg-video-vmware \
    xserver-xorg-video-qxl
  LC_ALL=C DEBIAN_FRONTEND=noninteractive update-initramfs -u
elif [ -e /bin/pacman ]; then
  sed -i 's/^MODULES=(/MODULES=(amdgpu radeon nouveau i915 virtio-gpu vmwgfx /g' /etc/mkinitcpio.conf
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed \
    xf86-video-ati xf86-video-amdgpu mesa vulkan-radeon libva-mesa-driver mesa-vdpau libva-utils nvtop \
    xf86-video-nouveau vulkan-nouveau \
    xf86-video-intel vulkan-intel libva-intel-driver \
    xf86-video-vmware \
    xf86-video-qxl
  mkinitcpio -P
fi

# apply skeleton to all users
getent passwd | while IFS=: read -r username x uid gid gecos home shell; do
  if [ -n "$home" ] && [ -d "$home" ] && [ "$home" != "/" ]; then
    if [ "$uid" -eq 0 ] || [ "$uid" -ge 1000 ]; then
      echo ":: apply skeleton to $home [$username $uid:$gid]"
      rsync -a --chown=$uid:$gid /etc/skel/ "$home"
    fi
  fi
done

# enable cockpit
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install cockpit cockpit-storaged cockpit-packagekit
  systemctl enable cockpit.socket
  firewall-offline-cmd --zone=public --add-port=9090/tcp
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm cockpit cockpit-storaged cockpit-packagekit
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
