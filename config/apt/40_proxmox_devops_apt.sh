#!/usr/bin/env bash

if grep -q Ubuntu /proc/version; then
    [ -f "${0}" ] && rm -- "${0}"
    exit 0
fi

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

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
_cpu_cores=$(grep '^core id' /proc/cpuinfo | sort -u | wc -l)

# debian router
yq -y '(.setup.distro) = "debian"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["router","tar-image"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso --no-autoreboot
_package_manager=$(yq -r '.setup as $setup | .distros[$setup.distro]' config/setup.yml)
env "HOME=$BUILDDIR/home" PACKER_LOG=1 PACKER_LOG_PATH=output/devops-linux.log \
    PKR_VAR_package_manager="${_package_manager}" PKR_VAR_package_cache="false" \
    PKR_VAR_headless="true" PKR_VAR_cpu_cores="${_cpu_cores}" PKR_VAR_memory="2048" \
    /bin/packer build -force -only=qemu.default devops-linux.pkr.hcl
if [ -f output/artifacts/tar/devops-linux-debian.tar.zst ]; then
  mv output/artifacts/tar/devops-linux-debian.tar.zst /var/lib/vz/template/cache/debian-x86_64-router.tar.zst
  pct create 400 /var/lib/vz/template/cache/debian-x86_64-router.tar.zst --ignore-unpack-errors 1 --memory 1536 \
    --hostname debian-router --storage local --swap 512 --rootfs local:64 \
    --net0 name=eth0,bridge=vmbr0,firewall=0,ip=dhcp,ip6=dhcp \
    --net1 name=eth1,bridge=vmbrlan0,firewall=0,ip=manual,ip6=manual \
    --unprivileged 1 --pool pool0 --ostype debian --onboot 1 --features nesting=1 --protection 1
fi

# archlinux mirror server
yq -y '(.setup.distro) = "archlinux"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["mirror","tar-image"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso --no-autoreboot
_package_manager=$(yq -r '.setup as $setup | .distros[$setup.distro]' config/setup.yml)
env "HOME=$BUILDDIR/home" PACKER_LOG=1 PACKER_LOG_PATH=output/devops-linux.log \
    PKR_VAR_package_manager="${_package_manager}" PKR_VAR_package_cache="false" \
    PKR_VAR_headless="true" PKR_VAR_cpu_cores="${_cpu_cores}" PKR_VAR_memory="2048" \
    /bin/packer build -force -only=qemu.default devops-linux.pkr.hcl
if [ -f output/artifacts/tar/devops-linux-archlinux.tar.zst ]; then
  mv output/artifacts/tar/devops-linux-archlinux.tar.zst /var/lib/vz/template/cache/archlinux-x86_64-mirror.tar.zst
  pct create 401 /var/lib/vz/template/cache/archlinux-x86_64-mirror.tar.zst --ignore-unpack-errors 1 --memory 1536 \
    --hostname arch-mirror --storage local --swap 512 --rootfs local:512 \
    --net0 name=eth0,bridge=vmbrlan0,firewall=0,ip=dhcp,ip6=dhcp \
    --unprivileged 1 --pool pool0 --ostype archlinux --onboot 1 --features nesting=1 --protection 1
fi

# debian 13 mirror server
yq -y '(.setup.distro) = "debian-13"' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.options) = ["mirror","tar-image"]' config/setup.yml | sponge config/setup.yml
yq -y '(.setup.target) = "/dev/vda"' config/setup.yml | sponge config/setup.yml
./cidata.sh --archiso --no-autoreboot
_package_manager=$(yq -r '.setup as $setup | .distros[$setup.distro]' config/setup.yml)
env "HOME=$BUILDDIR/home" PACKER_LOG=1 PACKER_LOG_PATH=output/devops-linux.log \
    PKR_VAR_package_manager="${_package_manager}" PKR_VAR_package_cache="false" \
    PKR_VAR_headless="true" PKR_VAR_cpu_cores="${_cpu_cores}" PKR_VAR_memory="2048" \
    /bin/packer build -force -only=qemu.default devops-linux.pkr.hcl
if [ -f output/artifacts/tar/devops-linux-debian-13.tar.zst ]; then
  mv output/artifacts/tar/devops-linux-debian-13.tar.zst /var/lib/vz/template/cache/debian-13-x86_64-mirror.tar.zst
  pct create 402 /var/lib/vz/template/cache/debian-13-x86_64-mirror.tar.zst --ignore-unpack-errors 1 --memory 1536 \
    --hostname debian-13-mirror --storage local --swap 512 --rootfs local:512 \
    --net0 name=eth0,bridge=vmbrlan0,firewall=0,ip=dhcp,ip6=dhcp \
    --unprivileged 1 --pool pool0 --ostype debian --onboot 1 --features nesting=1 --protection 1
else
  echo "Files in output/artifacts/tar/:"
  ls -la output/artifacts/tar
fi

# exit build environment
popd
popd

# sync everything to disk
sync

# cleanup
#rm -r "$BUILDDIR"
[ -f "${0}" ] && rm -- "${0}"
