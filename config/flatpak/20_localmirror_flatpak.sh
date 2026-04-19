#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ ${#line[@]} -eq 0 ] && continue; TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install nginx flatpak
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed nginx flatpak
fi
mkdir -p /srv/flathub/.ostree/repo

# initialize flatpak
FLATPAK_REPO_URL="$(yq -r '.setup.flatpak_mirror.flatpakrepo_url' /var/lib/cloud/instance/config/setup.yml)"
LC_ALL=C yes | flatpak remote-delete --system flathub
flatpak remote-add --system flathub "${FLATPAK_REPO_URL}"
flatpak remote-modify --collection-id=org.flathub.Stable flathub
flatpak remotes --columns=name,url

# prepare flatpak applications
while read -r line; do
  if [ -n "$line" ]; then
    echo "[ ## ] install $line"
    flatpak install --reinstall --system --noninteractive --assumeyes flathub "$line"
  fi
done <<<"$(yq -r '.setup.flatpak_mirror.mirror_refs[]' /var/lib/cloud/instance/config/setup.yml)"

# create gpg key for signed summary files
# [!] flathub does not support password protected gpg keys
cat >/tmp/gpgkey.txt <<EOF
%no-protection
%echo Generating basic OpenPGP signing key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: Flatpak Mirror Signing Key
Name-Comment: Flatpak Mirror Signing Key
Name-Email: flatpak-mirror@internal.invalid
Expire-Date: 0
%commit
%echo done
EOF
gpg --batch --generate-key /tmp/gpgkey.txt
rm /tmp/gpgkey.txt

# import flathub gpg key
curl -sL "${FLATPAK_REPO_URL}" | grep GPGKey | cut -d= -f2 | base64 -d | gpg --import -

# fix gpg IOCTL error
echo use-agent >> ~/.gnupg/gpg.conf
echo "pinentry-mode loopback" >> ~/.gnupg/gpg.conf
echo allow-loopback-pinentry >> ~/.gnupg/gpg-agent.conf

# export all gpg public keys and create flatpakrepo file
gpg --export "flathub@flathub.org" "flatpak-mirror@internal.invalid" > /srv/flathub/.ostree/repo/flathub-mirror.gpg
curl -sL "${FLATPAK_REPO_URL}" > /srv/flathub/.ostree/repo/flathub.flatpakrepo
sed -i "s|^Url=.*|Url=http://$(head -n1 /etc/hostname):8080/repo/|g" /srv/flathub/.ostree/repo/flathub.flatpakrepo
sed -i "s|^GPGKey=.*|GPGKey=$(base64 -w0 /srv/flathub/.ostree/repo/flathub-mirror.gpg)|g" /srv/flathub/.ostree/repo/flathub.flatpakrepo

tee /usr/local/bin/flatsync.sh <<'EOF'
#!/usr/bin/env bash

echo "[ ## ] update all flatpaks"
flatpak update --noninteractive --assumeyes

# fix partially installed runtimes and extensions
for i in $(flatpak list --all --columns=ref,origin | grep flathub | cut -d$'\t' -f1); do
  echo "[ ## ] reinstall $i"
  flatpak install --reinstall --system --noninteractive --assumeyes flathub "$i"
done

# export everything to disk
for i in $(flatpak list --all --columns=ref,origin | grep flathub | cut -d$'\t' -f1); do
  echo "[ ## ] export $i"
  flatpak create-usb --allow-partial /srv/flathub "$i"
done

# convert usb-setup to an actual repository
if ! [ -L "/srv/flathub/.ostree/repo/refs/heads" ] && [ -d "/srv/flathub/.ostree/repo/refs/heads" ]; then
  rm -rf "/srv/flathub/.ostree/repo/refs/heads"
  ln -s mirrors/org.flathub.Stable "/srv/flathub/.ostree/repo/refs/heads"
fi

# generate signed summary files
echo "[ ## ] generate signed summary"
flatpak build-update-repo --generate-static-deltas --gpg-sign="flatpak-mirror@internal.invalid" /srv/flathub/.ostree/repo
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
WorkingDirectory=/srv/flathub
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
        root /srv/flathub/.ostree;
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
        root /srv/flathub/.ostree;
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
