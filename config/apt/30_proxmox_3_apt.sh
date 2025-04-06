#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    ( ( sleep 1 && rm -- "${0}" ) & )
    exit 0
fi

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

# archlinux mirror server
yq -y '(.setup.distro) = "archlinux"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["mirror"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso
mv archlinux-x86_64-cidata.iso /var/lib/vz/template/iso/archlinux-x86_64-200-arch-mirror.iso
qm create 200 --net0 virtio,bridge=vmbr0 --name arch-mirror --ostype l26 --cores 2 --balloon 1280 --memory 1280 --machine q35 \
   --boot "order=virtio0;ide0" --virtio0 "local:0,format=qcow2,discard=on" --agent enabled=1 \
   --ide0 local:iso/archlinux-x86_64-200-arch-mirror.iso,media=cdrom --vga virtio \
   --onboot 1 --reboot 1 --serial0 socket --kvm 1 --protection 1
qm disk resize 200 virtio0 1024G

# debian mirror server
yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["mirror"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso
mv archlinux-x86_64-cidata.iso /var/lib/vz/template/iso/archlinux-x86_64-201-debian-mirror.iso
qm create 201 --net0 virtio,bridge=vmbr0 --name debian-mirror --ostype l26 --cores 2 --balloon 1280 --memory 1280 --machine q35 \
   --boot "order=virtio0;ide0" --virtio0 "local:0,format=qcow2,discard=on" --agent enabled=1 \
   --ide0 local:iso/archlinux-x86_64-201-debian-mirror.iso,media=cdrom --vga virtio \
   --onboot 1 --reboot 1 --serial0 socket --kvm 1 --protection 1
qm disk resize 201 virtio0 1024G

# podman debian server
yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["podman","dagu","cicd"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso
mv archlinux-x86_64-cidata.iso /var/lib/vz/template/iso/archlinux-x86_64-202-debian-podman.iso
qm create 202 --net0 virtio,bridge=vmbr0 --name debian-podman --ostype l26 --cores 2 --balloon 1280 --memory 1280 --machine q35 \
   --boot "order=virtio0;ide0" --virtio0 "local:0,format=qcow2,discard=on" --agent enabled=1 \
   --ide0 local:iso/archlinux-x86_64-202-debian-podman.iso,media=cdrom --vga virtio \
   --onboot 1 --reboot 1 --serial0 socket --kvm 1 --protection 1
qm disk resize 202 virtio0 512G

# exit build environment
popd
popd

# sync everything to disk
sync

# cleanup
rm -r "$BUILDDIR"
rm -- "${0}"
