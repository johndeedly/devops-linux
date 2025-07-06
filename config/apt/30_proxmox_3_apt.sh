#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    ( ( sleep 1 && rm -- "${0}" ) & )
    exit 0
fi
(
  source /etc/os-release
  if [ -n "${VERSION_CODENAME}" ] && [ "${VERSION_CODENAME}" != "bookworm" ]; then
    ( ( sleep 1 && rm -- "${0}" ) & )
    exit 0
  fi
)

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install packer cloud-image-utils xorriso ovmf

# setup build environment
mkdir -p /var/lib/vz/template/iso
BUILDDIR=$(mktemp --tmpdir=/var/tmp -d)
pushd "$BUILDDIR"
git clone https://github.com/johndeedly/devops-linux.git
pushd devops-linux

# debian router
yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["router"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso
mv archlinux-x86_64-cidata.iso /var/lib/vz/template/iso/archlinux-x86_64-300-debian-router.iso
qm create 300 --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=vmbrlan0 --name debian-router --ostype l26 --cores 2 --balloon 960 --memory 960 --machine q35 \
   --boot "order=virtio0;ide0" --virtio0 "local:0,format=qcow2,detect_zeroes=1,discard=on,iothread=1" --agent enabled=1 \
   --ide0 local:iso/archlinux-x86_64-300-debian-router.iso,media=cdrom --vga virtio \
   --onboot 1 --reboot 1 --serial0 socket --kvm 1 --protection 1
qm disk resize 300 virtio0 128G

# archlinux mirror server
yq -y '(.setup.distro) = "archlinux"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["mirror"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso
mv archlinux-x86_64-cidata.iso /var/lib/vz/template/iso/archlinux-x86_64-500-arch-mirror.iso
qm create 500 --net0 virtio,bridge=vmbrlan0 --name arch-mirror --ostype l26 --cores 2 --balloon 960 --memory 960 --machine q35 \
   --boot "order=virtio0;ide0" --virtio0 "local:0,format=qcow2,detect_zeroes=1,discard=on,iothread=1" --agent enabled=1 \
   --ide0 local:iso/archlinux-x86_64-500-arch-mirror.iso,media=cdrom --vga virtio \
   --onboot 0 --reboot 1 --serial0 socket --kvm 1 --protection 1
qm disk resize 500 virtio0 1T

# debian bookworm mirror server
yq -y '(.setup.distro) = "debian-12"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["mirror"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso
mv archlinux-x86_64-cidata.iso /var/lib/vz/template/iso/archlinux-x86_64-501-debian-mirror.iso
qm create 501 --net0 virtio,bridge=vmbrlan0 --name debian-bookworm-mirror --ostype l26 --cores 2 --balloon 960 --memory 960 --machine q35 \
   --boot "order=virtio0;ide0" --virtio0 "local:0,format=qcow2,detect_zeroes=1,discard=on,iothread=1" --agent enabled=1 \
   --ide0 local:iso/archlinux-x86_64-501-debian-mirror.iso,media=cdrom --vga virtio \
   --onboot 0 --reboot 1 --serial0 socket --kvm 1 --protection 1
qm disk resize 501 virtio0 1T

# ubuntu noble mirror server
yq -y '(.setup.distro) = "ubuntu-24"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["mirror"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso
mv archlinux-x86_64-cidata.iso /var/lib/vz/template/iso/archlinux-x86_64-502-ubuntu-mirror.iso
qm create 502 --net0 virtio,bridge=vmbrlan0 --name ubuntu-noble-mirror --ostype l26 --cores 2 --balloon 960 --memory 960 --machine q35 \
   --boot "order=virtio0;ide0" --virtio0 "local:0,format=qcow2,detect_zeroes=1,discard=on,iothread=1" --agent enabled=1 \
   --ide0 local:iso/archlinux-x86_64-502-ubuntu-mirror.iso,media=cdrom --vga virtio \
   --onboot 0 --reboot 1 --serial0 socket --kvm 1 --protection 1
qm disk resize 502 virtio0 1T

# podman debian server
yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["podman","dagu","cicd"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso
mv archlinux-x86_64-cidata.iso /var/lib/vz/template/iso/archlinux-x86_64-503-debian-podman.iso
qm create 503 --net0 virtio,bridge=vmbrlan0 --name debian-podman --ostype l26 --cores 2 --balloon 960 --memory 960 --machine q35 \
   --boot "order=virtio0;ide0" --virtio0 "local:0,format=qcow2,discard=on" --agent enabled=1 \
   --ide0 local:iso/archlinux-x86_64-503-debian-podman.iso,media=cdrom --vga virtio \
   --onboot 0 --reboot 1 --serial0 socket --kvm 1 --protection 1
qm disk resize 503 virtio0 512G

# exit build environment
popd
popd

# sync everything to disk
sync

# cleanup
rm -r "$BUILDDIR"
rm -- "${0}"
