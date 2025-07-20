#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# check if build chain is installed
if [ -e /bin/apt ] || [ -f /devops-linux ]; then
    # sync everything to disk
    sync
    # cleanup
    rm -- "${0}"
    # finished
    exit 0
fi
# otherwise a standard archiso off the shelf is expected from here on

# Wait for pacman keyring init to be done
systemctl restart pacman-init.service
while ! systemctl show pacman-init.service | grep SubState=exited; do
    systemctl --no-pager status -n0 pacman-init.service || true
    sleep 5
done

# check if archiso-mirror is configured
ARCHISO_MIRROR=$(python - <<DOC
import yaml
with open('/var/lib/cloud/instance/config/setup.yml') as f:
    data = yaml.safe_load(f)
    print(data['setup']['archiso_mirror'])
DOC
)
grep -qE "[hH][tT][tT][pP][sS]?[:]" - <<<"$ARCHISO_MIRROR" && tee /etc/pacman.d/mirrorlist <<<"Server = $ARCHISO_MIRROR" || \
# otherwise: time travel the repositories back to the build day of the iso
# the path year/month/day is resolved through the file "/version" in the archiso ram fs
tee /etc/pacman.d/mirrorlist <<<"Server = https://archive.archlinux.org/repos/$(head -1 /version | sed -e 's|\.|/|g')/\$repo/os/\$arch"

# Force ultimate trust on all existing keys in the pacman keyring
echo ":: modify archlinux keychain only for the old iso package versions, only for this installation step, to ultimate trust"
readonly homedir="$(pacman-conf GPGDir)"
FAKED_DAY_GPG=$(</version)
FAKED_DAY_GPG="${FAKED_DAY_GPG//./}T010000"
FAKED_DAY_PAC=$(</version)
FAKED_DAY_PAC="${FAKED_DAY_PAC//./-}"
CURRENT_DAY=$(date +"%Y-%m-%d")
gpg --homedir "$homedir" --no-permission-warning --list-keys --list-options show-only-fpr-mbox | sed -e '/archlinux[.]org$/!d' | sort -uk1 | while read -ra fpr_mbox; do
    echo "${fpr_mbox[0]}:6:"
done | gpg --faked-system-time "$FAKED_DAY_GPG" --allow-weak-key-signatures --homedir "$homedir" --no-permission-warning --import-ownertrust
gpg --faked-system-time "$FAKED_DAY_GPG" --allow-weak-key-signatures --homedir "$homedir" --no-permission-warning --check-trustdb

pacman -Sy --noconfirm
if [ -d "/iso/archiso/pkg" ] && [ -n "$(find /iso/archiso/pkg -type f)" ]; then
    rsync -av /iso/archiso/pkg/ /var/cache/pacman/pkg/
else
    pacman -Swp --logfile "/dev/null" --cachedir "/dev/null" libguestfs qemu-base jq yq libisoburn | while read -r line; do
        echo "$line"
        echo "$line".sig
    done | while read -r line; do
        echo ":: caching $line"
        curl -sL --output-dir /var/cache/pacman/pkg --remote-name "$line"
    done
fi
timedatectl set-ntp false
timedatectl set-time "$FAKED_DAY_PAC"
LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm libguestfs qemu-base jq yq libisoburn
timedatectl set-time "$CURRENT_DAY"
timedatectl set-ntp true

# sync everything to disk
sync

# cleanup
rm -- "${0}"
