#!/usr/bin/env bash

ARCHISOMODDED="archlinux-x86_64-cidata.iso"

# error handling
set -E -o functrace
err_report() {
    echo "errexit command '${1}' returned ${2} on line $(caller)" 1>&2
    [ -L "${ARCHISOMODDED}" ] && rm "$(readlink -f "${ARCHISOMODDED}")" && rm "${ARCHISOMODDED}"
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

# check yq is installed
if ! command -v yq 2>&1 >/dev/null
then
    if [ -n "$ismsys2env" ]; then
        wget -O /usr/bin/yq.exe https://github.com/mikefarah/yq/releases/download/v4.45.4/yq_windows_amd64.exe
    else
        echo 1>&2 "The command 'yq' could not be found. Please install yq to use this script."
        echo 1>&2 "archlinux: https://archlinux.org/packages/extra/x86_64/yq/"
        echo 1>&2 "debian: https://packages.debian.org/bookworm/yq"
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

# check packer is installed
if ! command -v packer 2>&1 >/dev/null
then
    if [ -n "$ismsys2env" ]; then
        pacman -S --noconfirm --needed unzip
        wget -O /usr/bin/packer.zip https://releases.hashicorp.com/packer/1.13.1/packer_1.13.1_windows_amd64.zip
        unzip /usr/bin/packer.zip -d /usr/bin
        mkdir -p /usr/share/licenses/packer
        mv /usr/bin/LICENSE.txt /usr/share/licenses/packer/LICENSE
        rm /usr/bin/packer.zip
    else
        echo 1>&2 "The command 'packer' could not be found. Please install packer to use this script."
        echo 1>&2 "archlinux: https://archlinux.org/packages/extra/x86_64/packer/"
        echo 1>&2 "debian: https://packages.debian.org/bookworm/packer"
        exit 1
    fi
fi

if [ -z "$ismsys2env" ]; then
    # check swtpm is installed
    if ! command -v swtpm 2>&1 >/dev/null
    then
        echo 1>&2 "The command 'swtpm' could not be found. Please install swtpm to use this script."
        echo 1>&2 "archlinux: https://archlinux.org/packages/extra/x86_64/swtpm/"
        echo 1>&2 "debian: https://packages.debian.org/bookworm/swtpm"
        exit 1
    fi
    
    # check ovmf is installed
    if ! [ -f /usr/share/OVMF/x64/OVMF_CODE.secboot.4m.fd ] && ! [ -f /usr/share/OVMF/OVMF_CODE_4M.secboot.fd ]; then
        echo 1>&2 "The uefi boot files could not be found. Please install the edk2-ovmf (Arch) or ovmf (Debian/Ubuntu) package to use this script."
        echo 1>&2 "archlinux: https://archlinux.org/packages/extra/any/edk2-ovmf/"
        echo 1>&2 "debian: https://packages.debian.org/bookworm/ovmf"
        exit 1
    fi
    
    # check qemu-system-x86_64 is installed
    if ! command -v qemu-system-x86_64 2>&1 >/dev/null
    then
        echo 1>&2 "The command 'qemu-system-x86_64' could not be found. Please install qemu-desktop to use this script."
        echo 1>&2 "archlinux: https://archlinux.org/packages/extra/x86_64/qemu-desktop/"
        echo 1>&2 "debian: https://packages.debian.org/bookworm/qemu-system-x86_64"
        exit 1
    fi
fi


_headless="true"
_vbox=0
_cache="false"
parse_parameters() {
    local _longopts="show-window,force-virtualbox,create-cache"
    local _opts="wvc"
    local _parsed=$(getopt --options=$_opts --longoptions=$_longopts --name "$0" -- "$@")
    # read getopt’s output this way to handle the quoting right:
    eval set -- "$_parsed"
    while true; do
        case "$1" in
            -w|--show-window)
                _headless="false"
                shift
                ;;
            -v|--force-virtualbox)
                _vbox=1
                shift
                ;;
            -c|--create-cache)
                _cache="true"
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


packer_buildappliance() {
    local _longopts="search,filter,args"
    local _opts="s:f:a:"
    local _parsed=$(getopt --options=$_opts --longoptions=$_longopts --name "$0" -- "$@")
    # read getopt’s output this way to handle the quoting right:
    eval set -- "$_parsed"
    local _search=""
    local _filter=""
    local _args=()
    while true; do
        case "$1" in
            -s|--search)
                _search="$2"
                shift 2
                ;;
            -f|--filter)
                _filter="$2"
                shift 2
                ;;
            -a|--args)
                _args=( $2 )
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "usage: packer_buildappliance [[-s|-f|-a] ...]+" 1>&2
                exit 1
                ;;
        esac
    done
    
    local _runit="YES"
    if [ -n "$_search" ]; then
        local _params=( -type f -name "$_search" )
        if [ -n "$_filter" ]; then
            _params+=( -wholename "$_filter" )
        fi
        find output "${_params[@]}" | while read -r line; do
            echo "$line"
            _runit=""
        done
    fi
    if [ -n "$_runit" ]; then
        _package_manager=$(yq -r '.setup as $setup | .distros[$setup.distro]' config/setup.yml)
        case $VIRTENV in
            wsl)
                # windows
                env PACKER_LOG=1 PACKER_LOG_PATH=output/devops-linux.log \
                    PKR_VAR_package_manager="${_package_manager}" PKR_VAR_package_cache="${_cache}" \
                    PKR_VAR_headless="${_headless}" /bin/packer "${_args[@]}"
                return $?
                ;;
            *)
                # others, including linux
                env PACKER_LOG=1 PACKER_LOG_PATH=output/devops-linux.log \
                    PKR_VAR_package_manager="${_package_manager}" PKR_VAR_package_cache="${_cache}" \
                    PKR_VAR_headless="${_headless}" /bin/packer "${_args[@]}"
                return $?
                ;;
        esac
    fi
    return -1
}

if [ -n "$ismsys2env" ]; then
    ./cidata.sh --archiso --no-autoreboot
else
    ./cidata.sh --archiso --isoinram --no-autoreboot
fi

mkdir -p output
if [ -n "$ismsys2env" ]; then
    VIRTENV="msys2"
else
    VIRTENV=$(systemd-detect-virt || true)
fi
case $VIRTENV in
    wsl|msys2)
        # windows
        packer_buildappliance -s "*devops-linux*.ova" -a "build -force -on-error=ask -only=virtualbox-iso.default devops-linux.pkr.hcl"
        ;;
    *)
        # others, including linux
        if [ $_vbox -eq 1 ]; then
          packer_buildappliance -s "*devops-linux*.ova" -a "build -force -on-error=ask -only=virtualbox-iso.default devops-linux.pkr.hcl"
        else
          packer_buildappliance -s "*devops-linux*.qcow2" -a "build -force -on-error=ask -only=qemu.default devops-linux.pkr.hcl"
        fi
        ;;
esac

[ -L "${ARCHISOMODDED}" ] && rm "$(readlink -f "${ARCHISOMODDED}")" && rm "${ARCHISOMODDED}"
