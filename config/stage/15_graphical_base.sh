#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

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
[ -f "${0}" ] && rm -- "${0}"
