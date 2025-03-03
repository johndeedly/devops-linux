#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start minecraft
PROJECTNAME="minecraft"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
volumes:
  mc-data:
services:
  main:
    image: itzg/minecraft-server
    restart: unless-stopped
    networks:
      - lan
    ports:
      - '25565:25565/tcp'
      - '19132:19132/udp'
    environment:
      EULA: true
      TYPE: NEOFORGE
      VERSION: 1.21.1
      NEOFORGE_VERSION: latest
      VIEW_DISTANCE: 10
      MEMORY: 2G
      MAX_PLAYERS: 5
      MOTD: Local Minecraft Create server
      PLUGINS: "https://cdn.modrinth.com/data/LNytGWDc/versions/IJpm7znS/create-1.21.1-6.0.1.jar\n
        https://cdn.modrinth.com/data/hSSqdyU1/versions/k0XmHBh4/Create%20Encased-1.21.1-1.7.0.jar\n
        https://cdn.modrinth.com/data/9enMEvoc/versions/cBxRUPWE/create_structures_arise-147.20.19-neoforge-1.21.1.jar\n
        
        https://cdn.modrinth.com/data/tpehi7ww/versions/BYUUUeZA/dungeons-and-taverns-v4.4.4.jar\n
        https://cdn.modrinth.com/data/8oi3bsk5/versions/MuJMtPGQ/Terralith_1.21.x_v2.5.8.jar\n
        https://cdn.modrinth.com/data/ZVzW5oNS/versions/pwe1kTJE/Incendium_1.21_UNSUPPORTED_PORT_v5.4.4.zip\n
        https://cdn.modrinth.com/data/LPjGiSO4/versions/dHJAVX8s/Nullscape_1.21.x_v1.2.10.jar\n
        
        https://cdn.modrinth.com/data/wKkoqHrH/versions/3rUDJIS0/geyser-neoforge-Geyser-Neoforge-2.4.4-b705.jar\n
        https://cdn.modrinth.com/data/bWrNNfkb/versions/YapRHgnZ/Floodgate-Neoforge-2.2.4-b38.jar\n
        https://cdn.modrinth.com/data/MPCX6s5C/versions/uZ2kVr2B/notenoughanimations-neoforge-1.9.2-mc1.21.jar"
    volumes:
      - mc-data:/data
EOF
pushd "${BUILDTMP}"
  podman-compose up --no-start
popd
pushd /etc/systemd/system
  podman generate systemd --new --name "${PROJECTNAME}_main_1" -f
popd
systemctl enable "container-${PROJECTNAME}_main_1"

firewall-offline-cmd --zone=public --add-port=25565/tcp
firewall-offline-cmd --zone=public --add-port=19132/udp

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
