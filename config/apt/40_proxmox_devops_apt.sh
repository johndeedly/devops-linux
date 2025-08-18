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
mkdir -p /var/lib/vz/template/{iso,cache}
BUILDDIR=$(mktemp --tmpdir=/var/tmp -d)
pushd "$BUILDDIR"
git clone https://github.com/johndeedly/devops-linux.git
mkdir -p "$BUILDDIR/home"
pushd devops-linux

sed -i 's|efi_firmware_code.*|efi_firmware_code = "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"|' devops-linux.pkr.hcl
sed -i 's|efi_firmware_vars.*|efi_firmware_vars = "/usr/share/OVMF/OVMF_VARS_4M.fd"|' devops-linux.pkr.hcl
mkdir -p output
env "HOME=$BUILDDIR/home" PACKER_LOG=1 PACKER_LOG_PATH=output/devops-linux.log \
    /bin/packer init devops-linux.pkr.hcl

# # debian router
# yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
# yq -y '(.setup.options) = ["router"]' config/setup.yml | sponge config/setup.yml
# yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
# ./cidata.sh --archiso
# mv archlinux-x86_64-cidata.iso /var/lib/vz/template/iso/archlinux-x86_64-200-debian-router.iso
# qm create 200 --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=vmbrlan0 --name debian-router --ostype l26 --cores 2 --balloon 960 --memory 960 --machine q35 \
#    --boot "order=virtio0;ide0" --virtio0 "local:128,format=qcow2,detect_zeroes=1,discard=on,iothread=1" --agent enabled=1 \
#    --ide0 local:iso/archlinux-x86_64-200-debian-router.iso,media=cdrom --vga virtio \
#    --onboot 1 --reboot 1 --serial0 socket --kvm 1

# archlinux mirror server
yq -y '(.setup.distro) = "archlinux"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["mirror","tar-image"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso --no-autoreboot
_package_manager=$(yq -r '.setup as $setup | .distros[$setup.distro]' config/setup.yml)
env "HOME=$BUILDDIR/home" PACKER_LOG=1 PACKER_LOG_PATH=output/devops-linux.log \
    PKR_VAR_package_manager="${_package_manager}" PKR_VAR_package_cache="false" \
    PKR_VAR_headless="true" PKR_VAR_cpu_cores="2" PKR_VAR_memory="1536" \
    /bin/packer build -force -only=qemu.default devops-linux.pkr.hcl
[ -f output/artifacts/tar/devops-linux-archlinux.tar.zst ] || exit 1
mv output/artifacts/tar/devops-linux-archlinux.tar.zst /var/lib/vz/template/cache/archlinux-x86_64-mirror.tar.zst
pct create 300 /var/lib/vz/template/cache/archlinux-x86_64-mirror.tar.zst --memory 1536 \
    --hostname arch-mirror --net0 name=eth0,bridge=vmbr0,firewall=0,ip=dhcp,ip6=dhcp --storage local --swap 512 --rootfs local:512 \
    --unprivileged 1 --pool pool0 --ostype archlinux --onboot 1 --features nesting=1

# debian 12 mirror server
yq -y '(.setup.distro) = "debian-12"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["mirror","tar-image"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso --no-autoreboot
_package_manager=$(yq -r '.setup as $setup | .distros[$setup.distro]' config/setup.yml)
env "HOME=$BUILDDIR/home" PACKER_LOG=1 PACKER_LOG_PATH=output/devops-linux.log \
    PKR_VAR_package_manager="${_package_manager}" PKR_VAR_package_cache="false" \
    PKR_VAR_headless="true" PKR_VAR_cpu_cores="2" PKR_VAR_memory="1536" \
    /bin/packer build -force -only=qemu.default devops-linux.pkr.hcl
[ -f output/artifacts/tar/devops-linux-debian-12.tar.zst ] || exit 1
mv output/artifacts/tar/devops-linux-debian-12.tar.zst /var/lib/vz/template/cache/debian-12-x86_64-mirror.tar.zst
pct create 301 /var/lib/vz/template/cache/debian-12-x86_64-mirror.tar.zst --memory 1536 \
    --hostname debian-12-mirror --net0 name=eth0,bridge=vmbr0,firewall=0,ip=dhcp,ip6=dhcp --storage local --swap 512 --rootfs local:512 \
    --unprivileged 1 --pool pool0 --ostype debian --onboot 1 --features nesting=1

# exit build environment
popd
popd

# sync everything to disk
sync

# cleanup
#rm -r "$BUILDDIR"
rm -- "${0}"
