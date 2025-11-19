#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    [ -f "${0}" ] && rm -- "${0}"
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

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

# create the cluster on first boot
tee /usr/local/bin/initialize-pve-cluster.sh <<EOF
#!/usr/bin/env bash
PROXMOX_CEPH_OSD_DEVICE="$(yq -r '.setup.proxmox_cluster.ceph_osd_device' /var/lib/cloud/instance/config/setup.yml)"

# initialize proxmox cluster
pvecm create lab
pvecm updatecerts --silent true
pvecm status
pvecm nodes

# configure ceph
pveceph mgr create
pveceph mon create
if [ -n "\$PROXMOX_CEPH_OSD_DEVICE" ]; then
  pveceph osd create "\$PROXMOX_CEPH_OSD_DEVICE"
fi

# enable proxmox cluster master mDNS advertising
tee /etc/systemd/dnssd/proxmoxcluster.dnssd <<EOX
[Service]
Name=%H
Type=_proxmoxcluster._tcp
SubType=_master
EOX
systemctl reload systemd-resolved.service

# sync everything to disk
sync

# cleanup
[ -f "\${0}" ] && rm -- "\${0}"
EOF
chmod +x /usr/local/bin/initialize-pve-cluster.sh
tee /etc/systemd/system/initialize-pve-cluster.service <<EOF
[Unit]
Description=Initialize a Proxmox cluster on first startup
ConditionPathExists=/usr/local/bin/initialize-pve-cluster.sh
After=pve-guests.service

[Service]
Type=oneshot
RemainAfterExit=true
StandardInput=null
StandardOutput=journal
StandardError=journal
ExecStart=/usr/local/bin/initialize-pve-cluster.sh

[Install]
WantedBy=multi-user.target
EOF
systemctl enable initialize-pve-cluster

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
