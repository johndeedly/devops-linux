#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# https://wiki.archlinux.org/title/File_systems
SUPPORTED_FILESYSTEMS=(
    bcachefs-tools
    btrfs-progs
    exfatprogs
    e2fsprogs
    f2fs-tools
    jfsutils
    nilfs-utils
    udftools
    dosfstools
    xfsprogs
    ecryptfs-utils
    erofs-utils
    squashfs-tools
    glusterfs
    kubo
    minio
    moosefs
    hdparm
    sdparm
    foremost
    nfs-utils
    nbd
)

# install packages
LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed "${SUPPORTED_FILESYSTEMS[@]}"

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
