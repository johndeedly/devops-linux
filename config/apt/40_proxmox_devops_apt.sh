#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    [ -f "${0}" ] && rm -- "${0}"
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

modprobe 9p
modprobe 9pnet
modprobe 9pnet_virtio

# locate the cidata iso and mount it to /iso
CIDATA_DEVICE=$(lsblk -no PATH,LABEL,FSTYPE | sed -e '/cidata/I!d' -e '/iso9660/I!d' | head -n1 | cut -d' ' -f1)
test -n "$CIDATA_DEVICE" && mount -o X-mount.mkdir "$CIDATA_DEVICE" /iso
mountpoint -q /iso || ( test -f /dev/disk/by-label/CIDATA && mount -o X-mount.mkdir /dev/disk/by-label/CIDATA /iso )
# fallback: locate the database mount (packer build) and mount it to /iso
mountpoint -q /iso || ( mount -t 9p -o X-mount.mkdir,trans=virtio,version=9p2000.L database.0 /iso || mount -t vboxsf -o X-mount.mkdir database.0 /iso )
# if iso mount is not present, quit
if ! mountpoint -q /iso; then
    [ -f "${0}" ] && rm -- "${0}"
    exit 0
fi

# prepare config arrays to iterate over
readarray QMS < <(yq -c '.setup.proxmox_devops.qms[]' /var/lib/cloud/instance/config/setup.yml)
readarray PCTS < <(yq -c '.setup.proxmox_devops.pcts[]' /var/lib/cloud/instance/config/setup.yml)

# setup build environment
mkdir -p /var/lib/vz/template/{iso,cache}
BUILDDIR=$(mktemp --tmpdir=/var/tmp -d)
pushd "$BUILDDIR"

# setup virtual machines
for line in "${QMS[@]}"; do
  read QM_IMAGE QM_ID QM_NAME QM_CORES QM_MEMORY QM_STORAGE QM_OSTYPE QM_POOL QM_ONBOOT QM_REBOOT < \
    <(jq '.image, .id, .name, .cores, .memory, .storage, .ostype, .pool, .onboot, .reboot' <<<"$line" | xargs)
  # check present
  if ! [ -f "/iso/$QM_IMAGE" ]; then
    unset QM_IMAGE QM_ID QM_NAME QM_CORES QM_MEMORY QM_STORAGE QM_OSTYPE QM_POOL QM_ONBOOT QM_REBOOT
    continue
  fi
  # create vm
  qm create "$QM_ID" --name "$QM_NAME" --ostype "$QM_OSTYPE" --cores "$QM_CORES" --memory "$QM_MEMORY" \
    --machine q35,viommu=virtio --kvm 1 --pool "$QM_POOL" \
    --agent enabled=1 --vga virtio --onboot "$QM_ONBOOT" --reboot "$QM_REBOOT" --serial0 socket
  # lvm -> raw, otherwise qcow2
  if pvs --rows | grep -E "VG.*$QM_STORAGE"; then
    qm disk import "$QM_ID" "/iso/$QM_IMAGE" "$QM_STORAGE" --format raw --target-disk virtio0
  else
    qm disk import "$QM_ID" "/iso/$QM_IMAGE" "$QM_STORAGE" --format qcow2 --target-disk virtio0
  fi
  qm set "$QM_ID" --boot order=virtio0
  # set network adapters
  readarray QM_NETWORKS < <(jq -c '.networks[]' <<<"$line")
  for net in "${QM_NETWORKS[@]}"; do
    read QM_NET_NAME QM_NET_BRIDGE QM_NET_VLAN < \
      <(jq '.name, .bridge, .vlan' <<<"$net" | xargs)
    qm set "$QM_ID" "--$QM_NET_NAME" "virtio,bridge=$QM_NET_BRIDGE,firewall=0,mtu=1500,tag=$QM_NET_VLAN"
    unset QM_NET_NAME QM_NET_BRIDGE QM_NET_VLAN
  done
  unset QM_IMAGE QM_ID QM_NAME QM_CORES QM_MEMORY QM_STORAGE QM_OSTYPE QM_POOL QM_ONBOOT QM_REBOOT
done

# setup containers
for line in "${PCTS[@]}"; do
  read PCT_IMAGE PCT_ID PCT_HOSTNAME PCT_CORES PCT_MEMORY PCT_STORAGE PCT_SIZE_GB PCT_OSTYPE PCT_POOL PCT_ONBOOT < \
    <(jq '.image, .id, .hostname, .cores, .memory, .storage, .size_gb, .ostype, .pool, .onboot' <<<"$line" | xargs)
  # check present
  if ! [ -f "/iso/$PCT_IMAGE" ]; then
    unset PCT_IMAGE PCT_ID PCT_HOSTNAME PCT_CORES PCT_MEMORY PCT_STORAGE PCT_SIZE_GB PCT_OSTYPE PCT_POOL PCT_ONBOOT
    continue
  fi
  # create container
  pct create "$PCT_ID" "/iso/$PCT_IMAGE" --ignore-unpack-errors 1 --cores "$PCT_CORES" --memory "$PCT_MEMORY" \
    --hostname "$PCT_HOSTNAME" --storage "$PCT_STORAGE" --rootfs "$PCT_STORAGE:$PCT_SIZE_GB" \
    --unprivileged 1 --pool "$PCT_POOL" --ostype "$PCT_OSTYPE" --onboot "$PCT_ONBOOT" --features nesting=1
  # set network adapters
  readarray PCT_NETWORKS < <(jq -c '.networks[]' <<<"$line")
  for net in "${PCT_NETWORKS[@]}"; do
    read PCT_NET_NAME PCT_NET_ALIAS PCT_NET_BRIDGE PCT_NET_IP PCT_NET_IP6 PCT_NET_VLAN < \
      <(jq '.name, .alias, .bridge, .ip, .ip6, .vlan' <<<"$net" | xargs)
    pct set "$PCT_ID" "--$PCT_NET_NAME" "name=$PCT_NET_ALIAS,bridge=$PCT_NET_BRIDGE,firewall=0,ip=$PCT_NET_IP,ip6=$PCT_NET_IP6,mtu=1500,tag=$PCT_NET_VLAN"
    unset PCT_NET_NAME PCT_NET_ALIAS PCT_NET_BRIDGE PCT_NET_IP PCT_NET_IP6 PCT_NET_VLAN
  done
  unset PCT_IMAGE PCT_ID PCT_HOSTNAME PCT_CORES PCT_MEMORY PCT_STORAGE PCT_SIZE_GB PCT_OSTYPE PCT_POOL PCT_ONBOOT
done

# Scheduled task to update all LXC containers on a regular basis
tee /usr/local/bin/update-all-lxcs.sh <<'EOF'
#!/usr/bin/env bash
# update all running containers

# list of container ids we need to iterate through
containers=( $(pct list | grep running | awk '{print $1}') )

pacman_update() {
  echo "[ ## $container] detected pacman"
  pct exec "$container" "LC_ALL=C yes | LC_ALL=C pacman -Syu --noconfirm"
}

apt_update() {
  echo "[ ## $container] detected apt"
  pct exec "$container" "apt-get update"
  pct exec "$container" "apt-get dist-upgrade -y"
  pct exec "$container" "apt-get clean"
  pct exec "$container" "apt-get autoremove -y"
}

yum_update() {
  echo "[ ## $container] detected yum"
  pct exec "$container" "yum -y update"
}

apk_update() {
  echo "[ ## $container] detected apk"
  pct exec "$container" "apk upgrade"
}

for container in $containers; do
  echo "[ ## ] create snapshot for $container"
  today="$(date +%F)"
  if pct snapshot "$container" "$today" --description "automatic snapshot taken on $today"; then
    echo "[ ## ] remove old snapshot for $container"
    daybeforeyesterday="$(date --date="-2 days" +%F)"
    pct delsnapshot "$container" "$daybeforeyesterday" --force true || true
  fi
  
  echo "[ ## ] updating $container"
  pct exec "$container" "which pacman >/dev/null" && pacman_update
  pct exec "$container" "which apt >/dev/null" && apt_update
  pct exec "$container" "which yum >/dev/null" && yum_update
  pct exec "$container" "which apk >/dev/null" && apk_update
done
EOF
chmod +x /usr/local/bin/update-all-lxcs.sh
tee /etc/systemd/system/update-all-lxcs.service <<EOF
[Unit]
Description=Update all LXC containers

[Service]
Type=simple
StandardInput=null
StandardOutput=journal
StandardError=journal
ExecStart=/usr/local/bin/update-all-lxcs.sh
EOF
tee /etc/systemd/system/update-all-lxcs.timer <<EOF
[Unit]
Description=Scheduled update of all LXC containers

[Timer]
OnCalendar=Tue,Thu,Sat 03:17

[Install]
WantedBy=multi-user.target
EOF
systemctl enable update-all-lxcs.timer

# exit build environment
popd

# sync everything to disk
sync

# cleanup
rm -r "$BUILDDIR"
[ -f "${0}" ] && rm -- "${0}"
