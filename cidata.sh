#!/usr/bin/env bash

# error handling
set -E -o functrace
err_report() {
    echo "errexit command '${1}' returned ${2} on line $(caller)" 1>&2
    exit "${2}"
}
trap 'err_report "${BASH_COMMAND}" "${?}"' ERR

_iso=1
_archiso=0
parse_parameters() {
    local _longopts="iso,archiso"
    local _opts="ia"
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
    "config/stage/ZZ_second_stage.sh:text/x-shellscript"
    "config/setup.yml:application/x-setup-config"
)
# pxe boot static files
while read -r line; do
    if [ -n "$line" ] && [ -e "$line" ]; then
        if [ -f "$line" ]; then
            mkdir -p "build/$(dirname $line)"
            tee "build/$line" >/dev/null <<EOF
$(dirname $line)
$(base64 -w 0 "$line")
EOF
            write_mime_params=( "${write_mime_params[@]}" "build/$line:application/x-provision-file" )
        fi
    fi
done <<<"$(find pxe -type f)"
# deployment scripts stage 1
while read -r line; do
    if [ -n "$line" ] && [ -e "config/$line" ]; then
        if [ -f "config/$line" ]; then
            write_mime_params=( "${write_mime_params[@]}" "config/$line:text/x-shellscript" )
        fi
    fi
done <<<"$(yq -r '.setup as $setup | .distros[$setup.distro] as $distro | .files[$distro][$setup.options[]][] | select(.stage==1) | .path' config/setup.yml)"
# deployment scripts stage 2
while read -r line; do
    if [ -n "$line" ] && [ -e "config/$line" ]; then
        if [ -f "config/$line" ]; then
            write_mime_params=( "${write_mime_params[@]}" "config/$line:application/x-per-boot" )
        fi
    fi
done <<<"$(yq -r '.setup as $setup | .distros[$setup.distro] as $distro | .files[$distro][$setup.options[]][] | select(.stage==2) | .path' config/setup.yml)"
write-mime-multipart --output=build/stage/user-data "${write_mime_params[@]}"

if [ $_archiso -eq 1 ]; then
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
        "build/stage/user-data:application/x-provision-config"
        "build/stage/meta-data:application/x-provision-config"
    )
    write-mime-multipart --output=build/archiso/user-data "${write_mime_params[@]}"

    echo "Download archiso when needed"
    ARCHISO=$(yq -r '.images.archiso' config/setup.yml)
    ARCHISOURL=$(yq -r '.download.archiso' config/setup.yml)
    if ! [ -e "${ARCHISO}" ]; then
        if ! wget -c -N --progress=dot:mega "${ARCHISOURL}"; then
            echo 1>&2 "Download error"
            exit 1
        fi
    fi

    echo "Append cidata to archiso"
    ARCHISOMODDED="archlinux-x86_64-cidata.iso"
    [ -f "${ARCHISOMODDED}" ] && rm "${ARCHISOMODDED}"
    xorriso -indev "${ARCHISO}" \
            -outdev "${ARCHISOMODDED}" \
            -volid CIDATA \
            -map build/archiso/ / \
            -map database/ / \
            -boot_image any replay
elif [ $_iso -eq 1 ]; then
    echo "Create cidata iso"
    CIDATAISO="cidata.iso"
    [ -f "${CIDATAISO}" ] && rm "${CIDATAISO}"
    xorriso -outdev "${CIDATAISO}" \
            -volid CIDATA \
            -map build/stage/ / \
            -map database/ /
else
    echo "no valid option, exiting"
    exit 1
fi
