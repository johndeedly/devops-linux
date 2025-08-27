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
PROXMOX_MASTER_IP="$(yq -r '.setup.proxmox_cluster.master_ip' /var/lib/cloud/instance/config/setup.yml)"
PROXMOX_BROADCAST_PORT_MASTER="$(yq -r '.setup.proxmox_cluster.broadcast_port_master' /var/lib/cloud/instance/config/setup.yml)"
PROXMOX_BROADCAST_PORT_WORKER="$(yq -r '.setup.proxmox_cluster.broadcast_port_worker' /var/lib/cloud/instance/config/setup.yml)"
PROXMOX_BROADCAST_RANGE="$(yq -r '.setup.proxmox_cluster.broadcast_range' /var/lib/cloud/instance/config/setup.yml)"
if [ -z "$PROXMOX_BROADCAST_PORT_MASTER" ]; then
    PROXMOX_BROADCAST_PORT_MASTER=17789
fi
if [ -z "$PROXMOX_BROADCAST_PORT_WORKER" ]; then
    PROXMOX_BROADCAST_PORT_WORKER=17790
fi
if [ -z "$PROXMOX_BROADCAST_RANGE" ]; then
    PROXMOX_BROADCAST_RANGE="0.0.0.0/0"
fi

# open firewall
ufw disable
ufw allow log "$PROXMOX_BROADCAST_PORT_WORKER/udp" comment 'allow cluster echo protocol (cli)'
ufw enable
ufw status verbose

# enable cluster key
# https://forum.proxmox.com/threads/etc-pve-priv-authorized_keys.18561/
mkdir -p /root/.ssh
tee -a /root/.ssh/id_ed25519 <<<"${PROXMOX_CLUSTER_KEY}"
chmod 0600 /root/.ssh/id_ed25519
tee -a /root/.ssh/id_ed25519.pub <<<"${PROXMOX_CLUSTER_PUB}"
chmod 0644 /root/.ssh/id_ed25519.pub

# broadcast for master
until [ -n "${PROXMOX_MASTER_IP}" ]; do
  echo "[ ## ] Broadcasting to master node..."
  IFS=',' read -r PROXMOX_CLIENT_IP PROXMOX_CLIENT_PORT PROXMOX_MASTER_IP < <(echo "ping" | socat -t 3 STDIO "UDP4-DATAGRAM:255.255.255.255:${PROXMOX_BROADCAST_PORT_MASTER},bind=:${PROXMOX_BROADCAST_PORT_WORKER},range=${PROXMOX_BROADCAST_RANGE},broadcast")
done
echo "[ ## ] Master node found: ${PROXMOX_MASTER_IP}, source: ${PROXMOX_CLIENT_IP}"
ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new root@"${PROXMOX_MASTER_IP}" 'exit'

# join the cluster
pvecm add "${PROXMOX_MASTER_IP}" --use_ssh true
pvecm updatecerts --silent true
pvecm status
pvecm nodes

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
