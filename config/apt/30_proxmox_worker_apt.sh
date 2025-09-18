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
tee -a /root/.ssh/id_ed25519 <<<"${PROXMOX_CLUSTER_KEY}"
chmod 0600 /root/.ssh/id_ed25519
tee -a /root/.ssh/id_ed25519.pub <<<"${PROXMOX_CLUSTER_PUB}"
chmod 0644 /root/.ssh/id_ed25519.pub

# enable proxmox cluster worker mDNS advertising
tee /etc/systemd/dnssd/proxmoxcluster.dnssd <<EOF
[Service]
Name=%H
Type=_proxmoxcluster._tcp
SubType=_worker
EOF

# broadcast for master
until [ -n "${PROXMOX_MASTER_FQDN_OR_IP}" ]; do
  echo "[ ## ] Broadcasting to master node..."
  PROXMOX_MASTER_FQDN_OR_IP=$(resolvectl query -p mdns --type=PTR --json=short _master._sub._proxmoxcluster._tcp.local 2>/dev/null | jq -r '.name')
done
echo "[ ## ] Master node configured: ${PROXMOX_MASTER_FQDN_OR_IP}"
ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new root@"${PROXMOX_MASTER_FQDN_OR_IP}" 'exit'

# join the cluster
pvecm add "${PROXMOX_MASTER_FQDN_OR_IP}" --use_ssh true
pvecm updatecerts --silent true
pvecm status
pvecm nodes

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
