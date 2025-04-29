#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

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
  curl --fail --silent --location --output /tmp/nvim-x86_64.tar.gz 'https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz'
  curl --fail --silent --location 'https://github.com/neovim/neovim/releases/download/stable/shasum.txt' | grep -oE '.*nvim-linux-x86_64.tar.gz' > /tmp/nvim-x86_64.tar.gz.sha256
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

# install basic packages
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
    systemd-homed build-essential yq \
    zstd rsyslog npm htop btop git \
    bash-completion ncdu pv mc ranger fzf moreutils \
    lshw libxml2 jq man manpages-de trash-cli \
    wireguard-tools nfs-kernel-server \
    gvfs gvfs-backends cifs-utils unzip p7zip rsync xdg-user-dirs xdg-utils \
    libnss-ldap libpam-ldap ldap-utils nslcd python3-pip python3-venv
  download_nerdfont
  download_starship
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
    luajit libluajit-5.1-dev lua-mpack lua-lpeg libunibilium-dev libmsgpack-dev libtermkey-dev
  download_neovim
  systemctl enable systemd-networkd systemd-resolved systemd-homed nslcd
  systemctl disable NetworkManager NetworkManager-wait-online NetworkManager-dispatcher || true
  systemctl mask NetworkManager NetworkManager-wait-online NetworkManager-dispatcher
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed \
    pacman-contrib starship ttf-terminus-nerd ttf-nerd-fonts-symbols powershell-bin base-devel neovim yq \
    zstd rsyslog npm htop btop git lazygit \
    bash-completion ncdu viu pv mc ranger fzf moreutils dotnet-runtime \
    lshw libxml2 jq core/man man-pages-de trash-cli \
    wireguard-tools nfs-utils \
    gvfs gvfs-smb cifs-utils unzip p7zip rsync xdg-user-dirs xdg-utils \
    openldap nss-pam-ldapd python-pip
  systemctl enable systemd-networkd systemd-resolved systemd-homed nslcd
  systemctl disable NetworkManager NetworkManager-wait-online NetworkManager-dispatcher || true
  systemctl mask NetworkManager NetworkManager-wait-online NetworkManager-dispatcher
  mkdir -p /etc/skel/.config/lazygit
  tee /etc/skel/.config/lazygit/config.yml <<EOF
git:
  merging:
    args: "--ff-only --autostash"
  log:
    showGraph: always
  branchLogCmd: "git log --graph --all --color=always --decorate --date=relative --oneline {{branchName}} --"
customCommands:
  - key: '<c-r>'
    context: 'localBranches'
    command: "git rebase --committer-date-is-author-date --ignore-date {{.SelectedLocalBranch.Name | quote}}"
    description: 'Rebase branch on selected branch ignoring commit and author dates'
    prompts:
      - type: 'confirm'
        title: 'Ignore commit and author dates'
        body: 'Reset all dates while rebasing {{.CheckedOutBranch.Name | quote}} on branch {{.SelectedLocalBranch.Name | quote}}?'
EOF
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C yum install -y \
    systemd-networkd cmake make automake gcc gcc-c++ kernel-devel \
    zstd rsyslog npm htop btop git \
    bash-completion ncdu pv mc ranger fzf moreutils \
    lshw libxml2 jq man-db trash-cli \
    wireguard-tools nfs-utils \
    gvfs gvfs-smb cifs-utils unzip p7zip rsync xdg-user-dirs xdg-utils \
    openldap openldap-clients nss-pam-ldapd python3-pip
  download_nerdfont
  download_starship
  LC_ALL=C yes | LC_ALL=C yum install -y \
    compat-lua-libs libtermkey libtree-sitter libvterm luajit luajit2.1-luv msgpack unibilium xsel
  download_neovim
  systemctl enable systemd-networkd systemd-resolved nslcd
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
( trap 'kill -- -$$' EXIT; HOME=/etc/skel /bin/bash -c 'nvim --headless -u "/etc/skel/.config/nvim/init.lua" -c ":Lazy sync | Lazy load all" -c ":MasonInstall beautysh lua-language-server stylua" -c ":qall!" || true' ) &
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
  sed -i 's|^uri .*|uri ldap://0.0.0.0/|' /etc/nslcd.conf
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
  if grep -q Debian /proc/version; then
    LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
      firmware-linux-nonfree \
      xserver-xorg-video-ati xserver-xorg-video-amdgpu mesa-vulkan-drivers mesa-vdpau-drivers nvtop \
      xserver-xorg-video-nvidia \
      xserver-xorg-video-intel \
      xserver-xorg-video-vmware \
      xserver-xorg-video-qxl
  elif grep -q Ubuntu /proc/version; then
    LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
      linux-firmware \
      xserver-xorg-video-ati xserver-xorg-video-amdgpu mesa-vulkan-drivers mesa-vdpau-drivers nvtop \
      xserver-xorg-video-intel \
      xserver-xorg-video-vmware \
      xserver-xorg-video-qxl
    NVIDIA_XORG_VERSION=$(LC_ALL=C apt list 'xserver-xorg-video-nvidia-*' | sed -e '/Listing/d' -e '/-server/d' -e '/-open/d' -e 's|/.*||g' | sort -r | head -n 1)
    if [ -n "${NVIDIA_XORG_VERSION}" ]; then
      LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install "${NVIDIA_XORG_VERSION}"
    fi
  fi
  tee /etc/modules-load.d/kms.conf <<EOF
$( for x in amdgpu radeon nvidia nvidia-modeset nvidia-uvm nvidia-drm i915 virtio-gpu vmwgfx ; do echo "$x"; done )
EOF
  tee /etc/modprobe.d/kms.conf <<EOF
$( for x in amdgpu radeon nvidia nvidia-modeset nvidia-uvm nvidia-drm i915 virtio-gpu vmwgfx ; do echo "options $x modeset=1"; done )
EOF
  tee /etc/initramfs-tools/hooks/zz_omit <<'EOF'
#!/bin/sh
PREREQ=""
case $1 in
prereqs)
  echo "$PREREQ"
  exit 0
  ;;
esac
. /usr/share/initramfs-tools/hook-functions
for x in amdgpu radeon nvidia nvidia-modeset nvidia-uvm nvidia-drm i915 virtio-gpu vmwgfx ; do
  find "${DESTDIR}" -type f -wholename "*${x}*" -print | while read -r line; do
    echo Remove mod/fw ${line#"$DESTDIR"} && rm "${line}"
  done
done
EOF
  chmod 755 /etc/initramfs-tools/hooks/zz_omit
  # ignore failed service when no nvidia card is present - the system is
  # not in a degraded state when this happens, nvidia...
  mkdir -p /etc/systemd/system/nvidia-persistenced.service.d
  tee /etc/systemd/system/nvidia-persistenced.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStopPost=
ExecStart=-/usr/bin/nvidia-persistenced --user nvpd
ExecStopPost=-/bin/rm -rf /var/run/nvidia-persistenced
EOF
  ls -1 /lib/modules | while read -r line; do
    depmod -a "$line"
  done
  LC_ALL=C DEBIAN_FRONTEND=noninteractive update-initramfs -u
  update-grub
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed \
    xf86-video-ati xf86-video-amdgpu mesa vulkan-radeon libva-mesa-driver mesa-vdpau libva-utils nvtop \
    nvidia nvidia-utils nvidia-prime libva-nvidia-driver \
    xf86-video-intel vulkan-intel libva-intel-driver \
    xf86-video-vmware \
    xf86-video-qxl
  tee /etc/modules-load.d/kms.conf <<EOF
$( for x in amdgpu radeon nvidia nvidia-modeset nvidia-uvm nvidia-drm i915 virtio-gpu vmwgfx ; do echo "$x"; done )
EOF
  tee /etc/modprobe.d/kms.conf <<EOF
$( for x in amdgpu radeon nvidia nvidia-modeset nvidia-uvm nvidia-drm i915 virtio-gpu vmwgfx ; do echo "options $x modeset=1"; done )
EOF
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

# sync everything to disk
sync

# cleanup
rm -- "${0}"
