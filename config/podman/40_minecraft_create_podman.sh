#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start minecraft
PROJECTNAME="create"
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
      MODS: "https://cdn.modrinth.com/data/LNytGWDc/versions/IJpm7znS/create-1.21.1-6.0.1.jar\n
        https://cdn.modrinth.com/data/hSSqdyU1/versions/k0XmHBh4/Create%20Encased-1.21.1-1.7.0.jar\n
        https://cdn.modrinth.com/data/9enMEvoc/versions/cBxRUPWE/create_structures_arise-147.20.19-neoforge-1.21.1.jar\n
        https://cdn.modrinth.com/data/MPCX6s5C/versions/uZ2kVr2B/notenoughanimations-neoforge-1.9.2-mc1.21.jar"
      PLUGINS: "https://cdn.modrinth.com/data/9eGKb6K1/versions/L9ZSz77F/voicechat-neoforge-1.21.1-2.5.26.jar\n
        https://cdn.modrinth.com/data/wKkoqHrH/versions/3rUDJIS0/geyser-neoforge-Geyser-Neoforge-2.4.4-b705.jar\n
        https://cdn.modrinth.com/data/bWrNNfkb/versions/YapRHgnZ/Floodgate-Neoforge-2.2.4-b38.jar"
      DATAPACKS: "https://cdn.modrinth.com/data/OhduvhIc/versions/8cEJouzY/Veinminer-1.2.4.zip\n
        https://cdn.modrinth.com/data/4sP0LXxp/versions/3D1S0vgH/Veinminer-Enchantment-1.2.3.zip\n
        https://cdn.modrinth.com/data/tpehi7ww/versions/9Dw6hgJA/Dungeons%20and%20Taverns%20v4.4.4.zip\n
        https://cdn.modrinth.com/data/8oi3bsk5/versions/urbokcOc/Terralith_1.21_v2.5.8.zip\n
        https://cdn.modrinth.com/data/ZVzW5oNS/versions/pwe1kTJE/Incendium_1.21_UNSUPPORTED_PORT_v5.4.4.zip\n
        https://cdn.modrinth.com/data/LPjGiSO4/versions/J4B2BaWk/Nullscape_1.21_v1.2.10.zip\n
        https://cdn.modrinth.com/data/7YjclEGc/versions/yCdCPMZa/dynamiclights-v1.8.5-mc1.17x-1.21x-datapack.zip"
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
