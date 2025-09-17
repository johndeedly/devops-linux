#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    [ -f "${0}" ] && rm -- "${0}"
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt install socat

# get cluster key
PROXMOX_CLUSTER_KEY="$(yq -r '.setup.proxmox_cluster.cluster_key' /var/lib/cloud/instance/config/setup.yml)"
PROXMOX_CLUSTER_PUB="$(yq -r '.setup.proxmox_cluster.cluster_pub' /var/lib/cloud/instance/config/setup.yml)"
PROXMOX_MASTER_FQDN_OR_IP="$(yq -r '.setup.proxmox_cluster.master_fqdn_or_ip' /var/lib/cloud/instance/config/setup.yml)"

# enable cluster key
# https://forum.proxmox.com/threads/etc-pve-priv-authorized_keys.18561/
mkdir -p /root/.ssh
if [ -f /root/.ssh/authorized_keys ]; then
  if ! [ -f /etc/pve/priv/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /etc/pve/priv/authorized_keys
  fi
  rm /root/.ssh/authorized_keys
  ln -s /etc/pve/priv/authorized_keys /root/.ssh/authorized_keys
fi
tee -a /root/.ssh/authorized_keys <<<"${PROXMOX_CLUSTER_PUB}"

# enable proxmox cluster master mDNS advertising
tee /etc/systemd/dnssd/proxmoxcluster.dnssd <<EOF
[Service]
Name=%H
Type=_proxmox_cluster._tcp
SubType=_master
EOF

# initialize proxmox cluster
pvecm create lab
pvecm updatecerts --silent true
pvecm status
pvecm nodes

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
