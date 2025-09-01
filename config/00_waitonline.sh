#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# wait online (not on rocky, as rocky does not have wait-online preinstalled)
if [ -f /usr/lib/systemd/systemd-networkd-wait-online ]; then
    SYSTEMD_VERSION=$(systemctl --version | head -n1 | cut -d' ' -f2)
    if [[ $SYSTEMD_VERSION -ge 258 ]]; then
        echo "[ ## ] Wait for any interface to be routable and dns resolver working (30s)"
        /usr/lib/systemd/systemd-networkd-wait-online --operational-state=routable --dns --any --timeout=30
    else
        echo "[ ## ] Wait for any interface to be routable (20s)"
        /usr/lib/systemd/systemd-networkd-wait-online --operational-state=routable --any --timeout=20
        echo "[ ## ] Wait for dns resolver (20s)"
        for i in $(seq 1 10); do
            getent hosts 1.1.1.1 >/dev/null 2>&1 && break
            sleep 2
        done
    fi
fi

# cleanup
[ -f "${0}" ] && rm -- "${0}"
