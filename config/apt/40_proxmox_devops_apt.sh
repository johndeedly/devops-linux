#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    [ -f "${0}" ] && rm -- "${0}"
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

modprobe 9p
modprobe 9pnet
modprobe 9pnet_virtio

# setup build environment
mkdir -p /var/lib/vz/template/{iso,cache}
BUILDDIR=$(mktemp --tmpdir=/var/tmp -d)
pushd "$BUILDDIR"
config_base="$(yq -r '.setup.local_http_database' /var/lib/cloud/instance/config/setup.yml)"

# debian router
target_path="/var/lib/vz/template/cache/debian-x86_64-router.qcow2"
packer_path="/run/database/proxmox-devops/debian-x86_64-router.qcow2"
config_http="${config_base%"/"}/proxmox-devops/debian-x86_64-router.qcow2"
container_hostname="debian-router"
if mountpoint -q /run/database || mount -t 9p -o X-mount.mkdir,trans=virtio,version=9p2000.L database.0 /run/database || mount -t vboxsf -o X-mount.mkdir database.0 /run/database; then
    rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r "$packer_path" "$target_path"
elif [ "x$config_base" != "x" ]; then
    wget -c -N --progress=dot:giga -O "$target_path" "$config_http"
fi
if [ -f "$target_path" ]; then
  qm create 400 --name "$container_hostname" --ostype other --cores 2 --balloon 1024 --memory 2048 --machine q35 \
    --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=vmbrlan0 \
    --agent enabled=1 --vga virtio --onboot 1 --reboot 1 --serial0 socket --kvm 1
  qm importdisk 400 "$target_path" local --format qcow2
  qm set 400 --virtio0 "local:400/vm-400-disk-0.qcow2,format=qcow2,detect_zeroes=1,discard=on,iothread=1"
  qm set 400 --boot "order=virtio0"
fi

# archlinux mirror server
target_path="/var/lib/vz/template/cache/archlinux-x86_64-mirror.tar.zst"
packer_path="/run/database/proxmox-devops/archlinux-x86_64-mirror.tar.zst"
config_http="${config_base%"/"}/proxmox-devops/archlinux-x86_64-mirror.tar.zst"
container_hostname="archlinux-mirror"
if mountpoint -q /run/database || mount -t 9p -o X-mount.mkdir,trans=virtio,version=9p2000.L database.0 /run/database || mount -t vboxsf -o X-mount.mkdir database.0 /run/database; then
    rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r "$packer_path" "$target_path"
elif [ "x$config_base" != "x" ]; then
    wget -c -N --progress=dot:giga -O "$target_path" "$config_http"
fi
if [ -f "$target_path" ]; then
  pct create 401 "$target_path" --ignore-unpack-errors 1 --memory 1536 \
    --hostname "$container_hostname" --storage local --swap 512 --rootfs local:512 \
    --net0 name=eth0,bridge=vmbrlan0,firewall=0,ip=dhcp,ip6=dhcp \
    --unprivileged 1 --pool pool0 --ostype archlinux --onboot 1 --features nesting=1 --protection 1
fi

# debian mirror server
target_path="/var/lib/vz/template/cache/debian-x86_64-mirror.tar.zst"
packer_path="/run/database/proxmox-devops/debian-x86_64-mirror.tar.zst"
config_http="${config_base%"/"}/proxmox-devops/debian-x86_64-mirror.tar.zst"
container_hostname="debian-mirror"
if mountpoint -q /run/database || mount -t 9p -o X-mount.mkdir,trans=virtio,version=9p2000.L database.0 /run/database || mount -t vboxsf -o X-mount.mkdir database.0 /run/database; then
    rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r "$packer_path" "$target_path"
elif [ "x$config_base" != "x" ]; then
    wget -c -N --progress=dot:giga -O "$target_path" "$config_http"
fi
if [ -f "$target_path" ]; then
  pct create 402 "$target_path" --ignore-unpack-errors 1 --memory 1536 \
    --hostname "$container_hostname" --storage local --swap 512 --rootfs local:512 \
    --net0 name=eth0,bridge=vmbrlan0,firewall=0,ip=dhcp,ip6=dhcp \
    --unprivileged 1 --pool pool0 --ostype debian --onboot 1 --features nesting=1 --protection 1
fi

# ubuntu mirror server
target_path="/var/lib/vz/template/cache/ubuntu-x86_64-mirror.tar.zst"
packer_path="/run/database/proxmox-devops/ubuntu-x86_64-mirror.tar.zst"
config_http="${config_base%"/"}/proxmox-devops/ubuntu-x86_64-mirror.tar.zst"
container_hostname="ubuntu-mirror"
if mountpoint -q /run/database || mount -t 9p -o X-mount.mkdir,trans=virtio,version=9p2000.L database.0 /run/database || mount -t vboxsf -o X-mount.mkdir database.0 /run/database; then
    rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r "$packer_path" "$target_path"
elif [ "x$config_base" != "x" ]; then
    wget -c -N --progress=dot:giga -O "$target_path" "$config_http"
fi
if [ -f "$target_path" ]; then
  pct create 403 "$target_path" --ignore-unpack-errors 1 --memory 1536 \
    --hostname "$container_hostname" --storage local --swap 512 --rootfs local:512 \
    --net0 name=eth0,bridge=vmbrlan0,firewall=0,ip=dhcp,ip6=dhcp \
    --unprivileged 1 --pool pool0 --ostype ubuntu --onboot 1 --features nesting=1 --protection 1
fi

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
