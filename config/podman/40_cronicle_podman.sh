#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# enable and start postgresql
PROJECTNAME="cronicle"
TMPDIR="$(mktemp -d)"
BUILDTMP="${TMPDIR}/${PROJECTNAME}"
mkdir -p "${BUILDTMP}"

mkdir "${BUILDTMP}/cronicle"
tee "${BUILDTMP}/cronicle/setup_cronicle.sh" <<'EOF'
#!/bin/bash

# This is the setup script for Cronicle
/opt/cronicle/bin/control.sh setup

# Additional commands or configurations, if needed
# ...
# chmod 777 /opt/cronicle/logs
# Start Cronicle (you can choose whether to start it immediately)
/opt/cronicle/bin/control.sh start

# Keep the container running
tail -f /dev/null
EOF
tee "${BUILDTMP}/cronicle/Dockerfile" <<'EOF'
# Use a base Node.js image suitable for your application
FROM node:18

# Set the working directory in the container
WORKDIR /app

# Install any dependencies required for the Cronicle installation
# You may need to adjust this based on your specific requirements
RUN apt-get update && apt-get install -y curl

# Run the installation command for Cronicle
RUN curl -s https://raw.githubusercontent.com/jhuckaby/Cronicle/master/bin/install.js | node

# Copy the setup script into the Docker image
COPY ./setup_cronicle.sh /app/

# Make the script executable
RUN chmod +x /app/setup_cronicle.sh
RUN chmod 777 /opt/cronicle/logs
EXPOSE 3012
# Specify the CMD to run the setup script when a container is started
CMD ["/app/setup_cronicle.sh"]
EOF

tee "${BUILDTMP}/podman-compose.yml" <<EOF
name: ${PROJECTNAME}
networks:
  lan:
services:
  main:
    build: ./cronicle
    restart: unless-stopped
    networks:
      - lan
    ports:
      - 13012:3012
EOF

pushd "${BUILDTMP}"
  podman-compose up --no-start
popd
pushd /etc/systemd/system
  podman generate systemd --new --name "${PROJECTNAME}_main_1" -f
popd
systemctl enable "container-${PROJECTNAME}_main_1"

firewall-offline-cmd --zone=public --add-port=13012/tcp

# sync everything to disk
sync

# cleanup
rm -r "${TMPDIR}"
rm -- "${0}"
