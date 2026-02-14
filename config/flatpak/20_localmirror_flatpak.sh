#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install nginx flatpak
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed nginx flatpak
fi
mkdir -p /srv/ostree/flathub

FLATPAK_HUB_URL="$(yq -r '.setup.flatpak_mirror.hub_url' /var/lib/cloud/instance/config/setup.yml)"
ostree init --repo=/srv/ostree/flathub --mode=archive --collection-id=org.flathub.Stable
ostree remote add --repo=/srv/ostree/flathub flathub "${FLATPAK_HUB_URL%/}"

wget -O /tmp/flathub.gpg https://dl.flathub.org/repo/flathub.gpg
ostree remote gpg-import --repo=/srv/ostree/flathub flathub -k /tmp/flathub.gpg

FLATPAK_REF_FILTER="$(yq -r '.setup.flatpak_mirror.ref_filter' /var/lib/cloud/instance/config/setup.yml)"
if [ -z "$FLATPAK_REF_FILTER" ] || [ "x$FLATPAK_REF_FILTER" == "xnull" ]; then
  FLATPAK_REF_FILTER="."
fi

ostree remote refs --repo=/srv/ostree/flathub flathub | sed -e 's/^flathub://g' | grep -E '^app/.*/x86_64/stable$' |
  grep -E "$FLATPAK_REF_FILTER" >/srv/ostree/flathub/x86_64.refs

tee /usr/local/bin/flatsync.sh <<'EOF'
#!/usr/bin/env bash

ostree pull --repo=/srv/ostree/flathub --disable-fsync --depth=1 --commit-metadata-only --mirror flathub
sync
xargs ostree pull --repo=/srv/ostree/flathub --disable-fsync --depth=1 --mirror flathub </srv/ostree/flathub/x86_64.refs
sync

ostree prune --repo=/srv/ostree/flathub --refs-only

ostree summary --repo=/srv/ostree/flathub -u

ostree fsck --repo=/srv/ostree/flathub
EOF
chmod +x /usr/local/bin/flatsync.sh

tee /etc/systemd/system/flatsync.service <<'EOF'
[Unit]
Description=Download up-to-date packages
StartLimitIntervalSec=30s
StartLimitBurst=5
After=network.target

[Service]
StandardInput=null
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=2s
WorkingDirectory=/srv/ostree
ExecStart=/usr/local/bin/flatsync.sh
EOF

tee /etc/systemd/system/flatsync.timer <<EOF
[Unit]
Description=Schedule up-to-date packages

[Timer]
OnBootSec=15min
OnCalendar=Tue,Thu,Sat 01:17

[Install]
WantedBy=multi-user.target
EOF

if [ -e /bin/apt ]; then
  tee /etc/nginx/nginx.conf <<EOF
user www-data;
worker_processes auto;
worker_cpu_affinity auto;

events {
    multi_accept on;
    worker_connections 1024;
}

http {
    charset utf-8;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    server_tokens off;
    log_not_found off;
    types_hash_max_size 4096;
    client_max_body_size 16M;

    server {
        listen 8080;
        listen [::]:8080;
        server_name $(cat /etc/hostname);
        root /srv/ostree;
        location / {
            try_files \$uri \$uri/ =404;
            autoindex on;
        }
    }

    # MIME
    include mime.types;
    default_type application/octet-stream;

    # logging
    access_log /var/log/www-access.log;
    error_log /var/log/www-error.log warn;

    # load configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
  rm /etc/nginx/sites-enabled/default
elif [ -e /bin/pacman ]; then
  tee /etc/nginx/nginx.conf <<EOF
user http;
worker_processes auto;
worker_cpu_affinity auto;

events {
    multi_accept on;
    worker_connections 1024;
}

http {
    charset utf-8;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    server_tokens off;
    log_not_found off;
    types_hash_max_size 4096;
    client_max_body_size 16M;

    server {
        listen 8080;
        listen [::]:8080;
        server_name $(cat /etc/hostname);
        root /srv/ostree;
        location / {
            try_files \$uri \$uri/ =404;
            autoindex on;
        }
    }

    # MIME
    include mime.types;
    default_type application/octet-stream;

    # logging
    access_log /var/log/www-access.log;
    error_log /var/log/www-error.log warn;

    # load configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
fi

systemctl enable nginx.service flatsync.timer

# enable flatpak mirror mDNS advertising
(
  source /etc/os-release
  tee /etc/systemd/dnssd/flatpakmirror.dnssd <<EOF
[Service]
Name=%H
Type=_flatpakmirror._tcp
Port=8080
EOF
)

ufw disable
ufw allow log 8080/tcp comment 'allow localmirror'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
