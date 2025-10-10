#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install nginx

mkdir -p /var/cache/apt/mirror /var/empty

if grep -q Ubuntu /proc/version; then
tee /usr/local/bin/aptsync.sh <<'EOF'
#!/usr/bin/env bash

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y update
/bin/apt-cache pkgnames 2>/dev/null | xargs /bin/apt download --print-uris 2>/dev/null | cut -d' ' -f1 | tr -d "'" > /tmp/mirror_url_list.txt
# force paths on downloaded files, skip domain part in path, continue unfinished downloads and skip already downloaded ones, use timestamps,
# download to target path, load download list from file, force progress bar when executed in tty and skip otherwise
wget -x -nH -c -N -P /var/cache/apt/mirror -i /tmp/mirror_url_list.txt --progress=bar:force:noscroll
# remove older package versions (sort -r: newest first) when packages count is larger than 3 (cnt[key]>3)
find /var/cache/apt/mirror -name '*.deb' -printf "%P %T+\n" | sort -r -t' ' -k2,2 | awk -F '_' '{
  key=$1
  for (i=2;i<NF-1;i++){key=sprintf("%s_%s",key,$i)}
  cnt[key]++
  if(cnt[key]>3){
    out=$1
    for (i=2;i<=NF;i++){out=sprintf("%s_%s",out,$i)}
    printf "%i %s\n",cnt[key],out
  }
}' | while read -r nr pkg ctm; do
  echo "removing /var/cache/apt/mirror/$pkg"
  rm "/var/cache/apt/mirror/$pkg"
done
(
  source /etc/os-release
  tee /tmp/mirror_url_list.txt <<EOX
http://archive.ubuntu.com/ubuntu/dists/${VERSION_CODENAME}/
http://archive.ubuntu.com/ubuntu/dists/${VERSION_CODENAME}-updates/
http://archive.ubuntu.com/ubuntu/dists/${VERSION_CODENAME}-backports/
http://archive.ubuntu.com/ubuntu/dists/${VERSION_CODENAME}-security/
EOX
)
# force paths on downloaded files, skip domain part in path, continue unfinished downloads and skip already downloaded ones, use timestamps,
# recursively traverse the page, stay below the given folder structure, exclude auto-generated index pages, exclude paths and files from other architectures,
# ignore robots.txt, download to target path, load download list from file, force progress bar when executed in tty and skip otherwise
wget -x -nH -c -N -r -np -R "index.html*" --reject-regex ".*-i386.*|.*debian-installer.*|.*dist-upgrader-all.*|.*source.*|.*[.]changelog|.*[.]deb" -e robots=off -P /var/cache/apt/mirror -i /tmp/mirror_url_list.txt --progress=bar:force:noscroll
rm /tmp/mirror_url_list.txt
EOF
else
tee /usr/local/bin/aptsync.sh <<'EOF'
#!/usr/bin/env bash

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y update
/bin/apt-cache pkgnames 2>/dev/null | xargs /bin/apt download --print-uris 2>/dev/null | cut -d' ' -f1 | tr -d "'" | \
  sed -e 's/mirror+file:\/etc\/apt\/mirrors\/debian\.list/https:\/\/deb.debian.org\/debian/g' \
  -e 's/mirror+file:\/etc\/apt\/mirrors\/debian-security\.list/https:\/\/deb.debian.org\/debian-security/g' > /tmp/mirror_url_list.txt
# force paths on downloaded files, skip domain part in path, continue unfinished downloads and skip already downloaded ones, use timestamps,
# download to target path, load download list from file, force progress bar when executed in tty and skip otherwise
wget -x -nH -c -N -P /var/cache/apt/mirror -i /tmp/mirror_url_list.txt --progress=bar:force:noscroll
# remove older package versions (sort -r: newest first) when packages count is larger than 3 (cnt[key]>3)
find /var/cache/apt/mirror -name '*.deb' -printf "%P %T+\n" | sort -r -t' ' -k2,2 | awk -F '_' '{
  key=$1
  for (i=2;i<NF-1;i++){key=sprintf("%s_%s",key,$i)}
  cnt[key]++
  if(cnt[key]>3){
    out=$1
    for (i=2;i<=NF;i++){out=sprintf("%s_%s",out,$i)}
    printf "%i %s\n",cnt[key],out
  }
}' | while read -r nr pkg ctm; do
  echo "removing /var/cache/apt/mirror/$pkg"
  rm "/var/cache/apt/mirror/$pkg"
done
(
  source /etc/os-release
  tee /tmp/mirror_url_list.txt <<EOX
https://deb.debian.org/debian/dists/${VERSION_CODENAME}/
https://deb.debian.org/debian/dists/${VERSION_CODENAME}-updates/
https://deb.debian.org/debian/dists/${VERSION_CODENAME}-backports/
https://deb.debian.org/debian-security/dists/${VERSION_CODENAME}-security/
http://download.proxmox.com/debian/pve/dists/${VERSION_CODENAME}/
EOX
)
# force paths on downloaded files, skip domain part in path, continue unfinished downloads and skip already downloaded ones, use timestamps,
# recursively traverse the page, stay below the given folder structure, exclude auto-generated index pages, exclude paths and files from other architectures,
# ignore robots.txt, download to target path, load download list from file, force progress bar when executed in tty and skip otherwise
wget -x -nH -c -N -r -np -R "index.html*" --reject-regex ".*-arm64.*|.*-armel.*|.*-armhf.*|.*-i386.*|.*-mips64el.*|.*-mipsel.*|.*-ppc64el.*|.*-s390x.*|.*source.*|.*[.]changelog|.*[.]deb" -e robots=off -P /var/cache/apt/mirror -i /tmp/mirror_url_list.txt --progress=bar:force:noscroll
rm /tmp/mirror_url_list.txt
EOF
# install the proxmox repository key
echo ":: download proxmox repository certificate"
(
  source /etc/os-release
  curl -fsSL "https://enterprise.proxmox.com/debian/proxmox-release-${VERSION_CODENAME}.gpg" | gpg --dearmor -o "/etc/apt/trusted.gpg.d/proxmox-release-${VERSION_CODENAME}.gpg"
)
# add the proxmox repository to the package sources
(
  source /etc/os-release
  tee /etc/apt/sources.list.d/pve-install-repo.list <<EOF
deb [arch=amd64] http://download.proxmox.com/debian/pve ${VERSION_CODENAME} pve-no-subscription
EOF
)
fi
chmod +x /usr/local/bin/aptsync.sh

tee /etc/systemd/system/aptsync.service <<'EOF'
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
WorkingDirectory=/var/cache/apt
ExecStart=/usr/local/bin/aptsync.sh
EOF

tee /etc/systemd/system/aptsync.timer <<EOF
[Unit]
Description=Schedule up-to-date packages

[Timer]
OnBootSec=15min
OnCalendar=Tue,Thu,Sat 01:17

[Install]
WantedBy=multi-user.target
EOF

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
        root /var/cache/apt/mirror;
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

systemctl enable nginx.service aptsync.timer

# enable pkgmirror mDNS advertising
if grep -q Ubuntu /proc/version; then
  tee /etc/systemd/dnssd/pkgmirror.dnssd <<EOF
[Service]
Name=%H
Type=_pkgmirror._tcp
SubType=_ubuntu
Port=8080
EOF
else
  tee /etc/systemd/dnssd/pkgmirror.dnssd <<EOF
[Service]
Name=%H
Type=_pkgmirror._tcp
SubType=_debian
Port=8080
EOF
fi

ufw disable
ufw allow log 8080/tcp comment 'allow localmirror'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
