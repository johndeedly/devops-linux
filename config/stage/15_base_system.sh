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

# install additional base packages
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
    build-essential rsyslog npm \
    libxml2 man manpages-de trash-cli \
    wireguard-tools nfs-kernel-server \
    gvfs gvfs-backends cifs-utils \
    python3-pip python3-venv
  download_nerdfont
  download_starship
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
    luajit libluajit-5.1-dev lua-mpack lua-lpeg libunibilium-dev libmsgpack-dev libtermkey-dev
  download_neovim
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed \
    pacman-contrib base-devel rsyslog npm \
    libxml2 core/man man-pages-de trash-cli \
    wireguard-tools nfs-utils \
    gvfs gvfs-smb cifs-utils \
    python-pip
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed \
    starship ttf-terminus-nerd ttf-nerd-fonts-symbols neovim
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C yum install -y \
    cmake make automake gcc gcc-c++ kernel-devel \
    rsyslog npm \
    libxml2 man-db trash-cli \
    wireguard-tools nfs-utils \
    gvfs gvfs-smb cifs-utils  \
    python3-pip
  download_nerdfont
  download_starship
  LC_ALL=C yes | LC_ALL=C yum install -y \
    compat-lua-libs libtermkey libtree-sitter libvterm luajit luajit2.1-luv msgpack unibilium xsel
  download_neovim
fi

# prepare NvChad environment
mkdir -p /etc/skel/.local/share
( trap 'kill -- -$$' EXIT; HOME=/etc/skel /bin/bash -c 'nvim --headless -u "/etc/skel/.config/nvim/init.lua" -c ":Lazy sync | Lazy load all" -c ":MasonInstall beautysh lua-language-server stylua" -c ":qall!" || true' ) &
pid=$!
wait $pid

# graphics driver for amd, intel, nvidia, vmware and virtio-gpu
if [ -e /bin/apt ]; then
  if grep -q Debian /proc/version; then
    LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
      firmware-linux-nonfree \
      xserver-xorg-video-ati xserver-xorg-video-amdgpu mesa-vulkan-drivers mesa-vdpau-drivers nvtop \
      xserver-xorg-video-nouveau \
      xserver-xorg-video-intel \
      xserver-xorg-video-vmware \
      xserver-xorg-video-qxl
  elif grep -q Ubuntu /proc/version; then
    LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
      linux-firmware \
      xserver-xorg-video-ati xserver-xorg-video-amdgpu mesa-vulkan-drivers mesa-vdpau-drivers nvtop \
      xserver-xorg-video-nouveau \
      xserver-xorg-video-intel \
      xserver-xorg-video-vmware \
      xserver-xorg-video-qxl
  fi
  tee /etc/modules-load.d/kms.conf <<EOF
$( for x in amdgpu radeon nouveau i915 virtio-gpu vmwgfx ; do echo "$x"; done )
EOF
  tee /etc/modprobe.d/kms.conf <<EOF
$( for x in amdgpu radeon nouveau i915 virtio-gpu vmwgfx ; do echo "options $x modeset=1"; done )
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
for x in amdgpu radeon nouveau i915 virtio-gpu vmwgfx ; do
  find "${DESTDIR}" -type f -wholename "*${x}*" -print | while read -r line; do
    echo Remove mod/fw ${line#"$DESTDIR"} && rm "${line}"
  done
done
EOF
  chmod 755 /etc/initramfs-tools/hooks/zz_omit
  ls -1 /lib/modules | while read -r line; do
    depmod -a "$line"
  done
  LC_ALL=C DEBIAN_FRONTEND=noninteractive update-initramfs -u
  update-grub
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed \
    xf86-video-ati xf86-video-amdgpu mesa vulkan-radeon libva-mesa-driver mesa-vdpau libva-utils nvtop \
    xf86-video-nouveau vulkan-nouveau \
    xf86-video-intel vulkan-intel libva-intel-driver \
    xf86-video-vmware \
    xf86-video-qxl
  tee /etc/modules-load.d/kms.conf <<EOF
$( for x in amdgpu radeon nouveau i915 virtio-gpu vmwgfx ; do echo "$x"; done )
EOF
  tee /etc/modprobe.d/kms.conf <<EOF
$( for x in amdgpu radeon nouveau i915 virtio-gpu vmwgfx ; do echo "options $x modeset=1"; done )
EOF
  tee /etc/initcpio/install/zz_omit <<'EOF'
#!/usr/bin/env bash

build() {
  for x in amdgpu radeon nouveau i915 virtio-gpu vmwgfx ; do
    find "${BUILDROOT}" -type f -wholename "*${x}*" -print | while read -r line; do
      echo Remove mod/fw ${line#"$BUILDROOT"} && rm "${line}"
    done
  done
}
EOF
  chmod 755 /etc/initcpio/install/zz_omit
  sed -i 's/^\(HOOKS=[^)]*\)/\1 zz_omit/' /etc/mkinitcpio.conf
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
