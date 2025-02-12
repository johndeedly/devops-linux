#!/usr/bin/env bash

# error handling
set -E -o functrace
err_report() {
    echo "errexit command '${1}' returned ${2} on line $(caller)" 1>&2
    exit "${2}"
}
trap 'err_report "${BASH_COMMAND}" "${?}"' ERR

# check wget is installed
if ! command -v wget 2>&1 >/dev/null
then
    echo 1>&2 "The command 'wget' could not be found. Please install wget to use this script."
    echo 1>&2 "archlinux: https://archlinux.org/packages/extra/x86_64/wget/"
    echo 1>&2 "debian: https://packages.debian.org/bookworm/wget"
    exit 1
fi

# check yq is installed
if ! command -v yq 2>&1 >/dev/null
then
    echo 1>&2 "The command 'yq' could not be found. Please install yq to use this script."
    echo 1>&2 "archlinux: https://archlinux.org/packages/extra/x86_64/yq/"
    echo 1>&2 "debian: https://packages.debian.org/bookworm/yq"
    exit 1
fi

# check write-mime-multipart is installed
if ! command -v write-mime-multipart 2>&1 >/dev/null
then
    echo 1>&2 "The command 'write-mime-multipart' could not be found. Please install cloud-image-utils to use this script."
    echo 1>&2 "archlinux: https://archlinux.org/packages/extra/any/cloud-image-utils/"
    echo 1>&2 "debian: https://packages.debian.org/bookworm/cloud-image-utils"
    exit 1
fi

# check packer is installed
if ! command -v packer 2>&1 >/dev/null
then
    echo 1>&2 "The command 'packer' could not be found. Please install packer to use this script."
    echo 1>&2 "archlinux: https://archlinux.org/packages/extra/x86_64/packer/"
    echo 1>&2 "debian: https://packages.debian.org/bookworm/packer"
    exit 1
fi

# check swtpm is installed
if ! command -v swtpm 2>&1 >/dev/null
then
    echo 1>&2 "The command 'swtpm' could not be found. Please install swtpm to use this script."
    echo 1>&2 "archlinux: https://archlinux.org/packages/extra/x86_64/swtpm/"
    echo 1>&2 "debian: https://packages.debian.org/bookworm/swtpm"
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
                    PKR_VAR_sound_driver=dsound PKR_VAR_accel_graphics=off \
                    PKR_VAR_package_manager="${_package_manager}" /bin/packer "${_args[@]}"
                return $?
                ;;
            *)
                # others, including linux
                env PACKER_LOG=1 PACKER_LOG_PATH=output/devops-linux.log \
                    PKR_VAR_sound_driver=pulse PKR_VAR_accel_graphics=on \
                    PKR_VAR_package_manager="${_package_manager}" /bin/packer "${_args[@]}"
                return $?
                ;;
        esac
    fi
    return -1
}

./cidata.sh --archiso

mkdir -p output
VIRTENV=$(systemd-detect-virt || true)
case $VIRTENV in
    wsl)
        # windows
        packer_buildappliance -s "*devops-linux*.ova" -a "build -force -on-error=ask -only=virtualbox-iso.default devops-linux.pkr.hcl"
        ;;
    *)
        # others, including linux
        packer_buildappliance -s "*devops-linux*.qcow2" -a "build -force -on-error=ask -only=qemu.default devops-linux.pkr.hcl"
        ;;
esac
