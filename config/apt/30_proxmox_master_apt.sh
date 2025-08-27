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
ufw allow log "$PROXMOX_BROADCAST_PORT_MASTER/udp" comment 'allow cluster echo protocol (srv)'
ufw enable
ufw status verbose

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

# listen for worker broadcasts
tee /etc/systemd/system/master-worker-cluster-broadcast.service <<EOF
[Unit]
Description=An echo service to broadcast the master ip to new worker nodes

[Service]
Type=simple
ExecStart=/bin/socat UDP4-RECVFROM:${PROXMOX_BROADCAST_PORT_MASTER},range=${PROXMOX_BROADCAST_RANGE},ip-pktinfo,broadcast,fork SYSTEM:'echo "\$\${SOCAT_PEERADDR},\$\${SOCAT_PEERPORT},\$\${SOCAT_IP_LOCADDR}"'
StandardError=journal
StandardInput=journal
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl enable master-worker-cluster-broadcast

# initialize proxmox cluster
pvecm create lab
pvecm updatecerts --silent true
pvecm status
pvecm nodes

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
