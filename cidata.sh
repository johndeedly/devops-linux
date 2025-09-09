#!/usr/bin/env bash

# error handling
set -E -o functrace
err_report() {
    echo "errexit command '${1}' returned ${2} on line $(caller)" 1>&2
    exit "${2}"
}
trap 'err_report "${BASH_COMMAND}" "${?}"' ERR

ismsys2env=""
if [ -f /etc/os-release ] && grep -E 'ID=msys2' /etc/os-release >/dev/null; then
  ismsys2env="YES"
fi

# check wget is installed
if ! command -v wget 2>&1 >/dev/null
then
    if [ -n "$ismsys2env" ]; then
        pacman -S --noconfirm --needed wget
    else
        echo 1>&2 "The command 'wget' could not be found. Please install wget to use this script."
        echo 1>&2 "archlinux: https://archlinux.org/packages/extra/x86_64/wget/"
        echo 1>&2 "debian: https://packages.debian.org/bookworm/wget"
        exit 1
    fi
fi

# check xorriso is installed
if ! command -v xorriso 2>&1 >/dev/null
then
    if [ -n "$ismsys2env" ]; then
        pacman -S --noconfirm xorriso
    else
        echo 1>&2 "The command 'xorriso' could not be found. Please install xorriso to use this script."
        echo 1>&2 "archlinux: https://archlinux.org/packages/extra/x86_64/libisoburn/"
        echo 1>&2 "debian: https://packages.debian.org/bookworm/xorriso"
        exit 1
    fi
fi

# check write-mime-multipart is installed
if ! command -v write-mime-multipart 2>&1 >/dev/null
then
    if [ -n "$ismsys2env" ]; then
        pacman -S --noconfirm --needed git python3
        git clone --depth=1 https://github.com/canonical/cloud-utils.git ~/cloud-utils
        cp ~/cloud-utils/bin/* /usr/bin/
        rm -rf ~/cloud-utils
    else
        echo 1>&2 "The command 'write-mime-multipart' could not be found. Please install cloud-image-utils to use this script."
        echo 1>&2 "archlinux: https://archlinux.org/packages/extra/any/cloud-image-utils/"
        echo 1>&2 "debian: https://packages.debian.org/bookworm/cloud-image-utils"
        exit 1
    fi
fi


_iso=1
_archiso=0
_ram=0
_autoreboot=1
_proxmox=0
parse_parameters() {
    local _longopts="iso,archiso,isoinram,no-autoreboot,proxmox"
    local _opts="iarnp:"
    local _parsed=$(getopt --options=$_opts --longoptions=$_longopts --name "$0" -- "$@")
    # read getopt’s output this way to handle the quoting right:
    eval set -- "$_parsed"
    while true; do
        case "$1" in
            -i|--iso)
                _iso=1
                _archiso=0
                shift
                ;;
            -a|--archiso)
                _archiso=1
                _iso=0
                shift
                ;;
            -r|--isoinram)
                _ram=1
                shift
                ;;
            -n|--no-autoreboot)
                _autoreboot=0
                shift
                ;;
            -p|--proxmox)
                _proxmox=1
                shift
                ;;
            --)
                shift
                break
                ;;
        esac
    done
}
parse_parameters "$@"


echo "Prepare CIDATA directories"
[ -n "$(find build -type f)" ] && find build -type f \( -not -name ".gitkeep" \) -delete
mkdir -p build/{archiso,stage}

tee build/archiso/meta-data build/stage/meta-data >/dev/null <<EOF
EOF

# prepare user-data for stage
write_mime_params=(
    "config/part-handler-setup.py:text/part-handler"
    "config/stage/bootup_stage.sh:text/cloud-boothook"
    "config/stage/environment.yml:text/cloud-config"
    "config/stage/network-setup.yml:text/cloud-config"
    "config/stage/i18n.yml:text/cloud-config"
    "config/stage/user-skeleton.yml:text/cloud-config"
    "config/stage/10_firstboot.sh:text/x-shellscript"
    "config/stage/18_ldap.sh:text/x-shellscript"
    "config/stage/18_syslog.sh:text/x-shellscript"
    "config/stage/18_syslog_server.sh:text/x-shellscript"
    "config/stage/90_second_stage.sh:text/x-shellscript"
    "config/stage/90_final_stage.sh:application/x-second-stage"
    "config/setup.yml:application/x-setup-config"
    "config/00_waitonline.sh:text/x-shellscript"
    "config/00_waitonline.sh:application/x-second-stage"
)
# deployment scripts stage 'config'
while read -r line; do
    if [ -n "$line" ] && [ -e "config/$line" ]; then
        if [ -f "config/$line" ]; then
            mkdir -p "build/$(dirname $line)"
            tee "build/$line" >/dev/null <<EOF
$(dirname $line)
$(base64 -w 0 "config/$line")
EOF
            write_mime_params=( "${write_mime_params[@]}" "build/$line:application/x-provision-file" )
        fi
    fi
done <<<"$(yq -r '.setup as $setup | .distros[$setup.distro] as $distro | .files[$distro][$setup.options[]][] | select(.config) | .path' config/setup.yml)"
# deployment scripts stage 1
if [ $_autoreboot -eq 1 ]; then
    write_mime_params=( "${write_mime_params[@]}" "config/99_autoreboot.sh:text/x-shellscript" )
fi
while read -r line; do
    if [ -n "$line" ] && [ -e "config/$line" ]; then
        if [ -f "config/$line" ]; then
            write_mime_params=( "${write_mime_params[@]}" "config/$line:text/x-shellscript" )
        fi
    fi
done <<<"$(yq -r '.setup as $setup | .distros[$setup.distro] as $distro | .files[$distro][$setup.options[]][] | select(.stage==1) | .path' config/setup.yml)"
# deployment scripts stage 2
if [ $_autoreboot -eq 1 ]; then
    write_mime_params=( "${write_mime_params[@]}" "config/98_lockdown.sh:application/x-second-stage" "config/99_autoreboot.sh:application/x-second-stage" )
fi
while read -r line; do
    if [ -n "$line" ] && [ -e "config/$line" ]; then
        if [ -f "config/$line" ]; then
            write_mime_params=( "${write_mime_params[@]}" "config/$line:application/x-second-stage" )
        fi
    fi
done <<<"$(yq -r '.setup as $setup | .distros[$setup.distro] as $distro | .files[$distro][$setup.options[]][] | select(.stage==2) | .path' config/setup.yml)"
write-mime-multipart --output=build/stage/user-data "${write_mime_params[@]}"

if [ $_archiso -eq 1 ] || [ $_proxmox -eq 1 ]; then
    # prepare user-data for archiso, packed with stage
    write_mime_params=(
        "config/part-handler-setup.py:text/part-handler"
        "config/archiso/bootup.sh:text/cloud-boothook"
        "config/archiso/environment.yml:text/cloud-config"
        "config/archiso/network-setup.yml:text/cloud-config"
        "config/archiso/i18n.yml:text/cloud-config"
        "config/archiso/10_environment.sh:text/x-shellscript"
        "config/archiso/15_system_base_setup.sh:text/x-shellscript"
        "config/archiso/20_bootable_system.sh:text/x-shellscript"
        "config/setup.yml:application/x-setup-config"
        "config/00_waitonline.sh:text/x-shellscript"
        "config/99_autoreboot.sh:text/x-shellscript"
        "build/stage/user-data:application/x-provision-config"
        "build/stage/meta-data:application/x-provision-config"
    )
    write-mime-multipart --output=build/archiso/user-data "${write_mime_params[@]}"

    ARCHISO=$(yq -r '.images.archiso' config/setup.yml)
    ARCHISOURL=$(yq -r '.download.archiso' config/setup.yml)
    DEBISO=$(yq -r '.images.debiso' config/setup.yml)
    
    if ! [ -e "${DEBISO}" ]; then
        if ! [ -e "${ARCHISO}" ]; then
            echo "Download archiso"
            if ! wget -c -N --progress=dot:giga "${ARCHISOURL}"; then
                echo 1>&2 "Download error"
                exit 1
            fi
        fi
        DEVOPSISO="${ARCHISO}"
    else
        DEVOPSISO="${DEBISO}"
    fi

    echo "Append cidata to devops-iso"
    DEVOPSISOMODDED="devops-x86_64-cidata.iso"
    [ -L "${DEVOPSISOMODDED}" ] && rm "$(readlink -f "${DEVOPSISOMODDED}")" && rm "${DEVOPSISOMODDED}"
    [ -f "${DEVOPSISOMODDED}" ] && rm "${DEVOPSISOMODDED}"
    if [ $_ram -eq 1 ]; then
        DEVOPSISOMODDED="$(mktemp -d)/devops-x86_64-cidata.iso"
        ln -s "${DEVOPSISOMODDED}" devops-x86_64-cidata.iso
    fi
    xorriso -indev "${DEVOPSISO}" \
            -outdev "${DEVOPSISOMODDED}" \
            -volid CIDATA \
            -map build/archiso/ / \
            -boot_image any replay
    
    if [ $_proxmox -eq 1 ]; then
        echo ":: Preparing proxmox"
        _proxmox_vm=0
        while [ $_proxmox_vm -lt 100 ] || [ $_proxmox_vm -gt 999999999 ]; do
            read -p "Enter proxmox vm id [100..999999999]: " _proxmox_vm
        done
        read -p "Enter proxmox vm name: " _proxmox_name
        _proxmox_name="${_proxmox_name// /-}"
        read -e -p "Enter proxmox vm core count [2]: " -i "2" _proxmox_cores
        read -e -p "Enter proxmox vm memory [2048]: " -i "2048" _proxmox_mem
        read -e -p "Enter proxmox vm bridge [vmbr0]: " -i "vmbr0" _proxmox_bridge
        read -e -p "Enter proxmox vm storage [local]: " -i "local" _proxmox_storage
        read -e -p "Enter proxmox vm size in GiB [512]: " -i "512" _proxmox_size
        mv "${DEVOPSISOMODDED}" "/var/lib/vz/template/iso/devops-x86_64-${_proxmox_vm}-${_proxmox_name}.iso"
        if pvs --rows | grep -E "VG ${_proxmox_storage}\$"
        then
            if ! qm create "${_proxmox_vm}" --net0 "virtio,bridge=${_proxmox_bridge}" --name "${_proxmox_name}" \
            --ostype l26 --cores "${_proxmox_cores}" --memory "${_proxmox_mem}" --machine q35 --bios ovmf \
            --boot "order=virtio0;ide0" --virtio0 "${_proxmox_storage}:${_proxmox_size},discard=on,iothread=1,size=${_proxmox_size}" --agent enabled=1 \
            --efidisk0 "${_proxmox_storage}:0,efitype=4m,format=raw,pre-enrolled-keys=0" --tpmstate0 "${_proxmox_storage}:0,version=v2.0" \
            --ide0 "local:iso/devops-x86_64-${_proxmox_vm}-${_proxmox_name}.iso,media=cdrom" --vga virtio
            then
                rm "/var/lib/vz/template/iso/devops-x86_64-${_proxmox_vm}-${_proxmox_name}.iso"
            fi
        else
            if ! qm create "${_proxmox_vm}" --net0 "virtio,bridge=${_proxmox_bridge}" --name "${_proxmox_name}" \
            --ostype l26 --cores "${_proxmox_cores}" --memory "${_proxmox_mem}" --machine q35 --bios ovmf \
            --boot "order=virtio0;ide0" --virtio0 "${_proxmox_storage}:0,format=qcow2,discard=on,iothread=1" --agent enabled=1 \
            --efidisk0 "${_proxmox_storage}:0,efitype=4m,format=raw,pre-enrolled-keys=0" --tpmstate0 "${_proxmox_storage}:0,version=v2.0" \
            --ide0 "local:iso/devops-x86_64-${_proxmox_vm}-${_proxmox_name}.iso,media=cdrom" --vga virtio
            then
                rm "/var/lib/vz/template/iso/devops-x86_64-${_proxmox_vm}-${_proxmox_name}.iso"
            else
              qm disk resize "${_proxmox_vm}" virtio0 "${_proxmox_size}G"
            fi
        fi
    fi
elif [ $_iso -eq 1 ]; then
    echo "Create cidata iso"
    CIDATAISO="cidata.iso"
    [ -L "${CIDATAISO}" ] && rm "$(readlink -f "${CIDATAISO}")" && rm "${CIDATAISO}"
    [ -f "${CIDATAISO}" ] && rm "${CIDATAISO}"
    if [ $_ram -eq 1 ]; then
        CIDATAISO="$(mktemp -d)/cidata.iso"
        ln -s "${CIDATAISO}" cidata.iso
    fi
    xorriso -outdev "${CIDATAISO}" \
            -volid CIDATA \
            -map build/stage/ /
else
    echo "no valid option, exiting"
    exit 1
fi
