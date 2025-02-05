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

echo "Prepare CIDATA directory"
[ -n "$(find build -type f)" ] && find build -type f \( -not -name ".gitkeep" \) -delete
mkdir -p build/{archiso,stage,CIDATA}

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

# finalize CIDATA
cp build/archiso/user-data build/archiso/meta-data build/CIDATA/

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
		-map build/CIDATA/ / \
        -map database/ / \
        -boot_image any replay

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
