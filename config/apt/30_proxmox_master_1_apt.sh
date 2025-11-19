#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    [ -f "${0}" ] && rm -- "${0}"
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# install ceph
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install cephadm ceph-mon ceph-mgr ceph-osd ceph-common ceph-base

# initialize the ceph cluster on the master
PROXMOX_CEPH_COMM_NETWORK="$(yq -r '.setup.proxmox_cluster.ceph_comm_network' /var/lib/cloud/instance/config/setup.yml)"
if [ -n "$PROXMOX_CEPH_COMM_NETWORK" ]; then
  pveceph init --network "$PROXMOX_CEPH_COMM_NETWORK"
else
  pveceph init
fi

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
