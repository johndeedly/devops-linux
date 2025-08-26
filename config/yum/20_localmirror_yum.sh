#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C yum install -y nginx

mkdir -p /var/cache/yum/mirror /var/empty

tee /usr/local/bin/yumsync.sh <<'EOF'
#!/usr/bin/env bash

tee /tmp/mirror_url_list.txt <<EOX
https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9
https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-rockyofficial
https://dl.rockylinux.org/pub/rocky/fullfilelist
https://dl.rockylinux.org/pub/rocky/fullfiletimelist
https://dl.rockylinux.org/pub/rocky/fullfiletimelist-rocky
https://dl.rockylinux.org/pub/rocky/fullfiletimelist-rocky-linux
https://dl.rockylinux.org/pub/rocky/fullfiletimelist-rocky-old
https://dl.rockylinux.org/pub/rocky/imagelist-rocky
https://dl.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/
https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/
https://dl.rockylinux.org/pub/rocky/9/CRB/x86_64/os/
https://dl.rockylinux.org/pub/rocky/9/extras/x86_64/os/
https://mirror.rackspace.com/epel/9/Everything/x86_64/
https://codecs.fedoraproject.org/openh264/epel/9/x86_64/os/
EOX
# force paths on downloaded files, skip domain part in path, continue unfinished downloads and skip already downloaded ones, use timestamps,
# recursively traverse the page, stay below the given folder structure, exclude auto-generated index pages, exclude paths and files from other architectures,
# ignore robots.txt, download to target path, load download list from file, force progress bar when executed in tty and skip otherwise
wget -x -nH -c -N -r -np -R "index.html*" --reject-regex ".*[.]i686[.]rpm.*" -e robots=off -P /var/cache/yum/mirror -i /tmp/mirror_url_list.txt --progress=bar:force:noscroll
# remove older package versions (sort -r: newest first) when packages count is larger than 3 (cnt[key]>3)
find /var/cache/yum/mirror -name '*.rpm' -printf "%P %T+\n" | sort -r -t' ' -k2,2 | awk -F '-' '{
  key=$1
  for (i=2;i<NF-3;i++){key=sprintf("%s-%s",key,$i)}
  cnt[key]++
  if(cnt[key]>3){
    out=$1
    for (i=2;i<=NF;i++){out=sprintf("%s-%s",out,$i)}
    printf "%i %s\n",cnt[key],out
  }
}' | while read -r nr pkg ctm; do
  echo "removing /var/cache/yum/mirror/$pkg"
  rm "/var/cache/yum/mirror/$pkg"
done
rm /tmp/mirror_url_list.txt
EOF
chmod +x /usr/local/bin/yumsync.sh

tee /etc/systemd/system/yumsync.service <<'EOF'
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
WorkingDirectory=/var/cache/yum
ExecStart=/usr/local/bin/yumsync.sh
EOF

tee /etc/systemd/system/yumsync.timer <<EOF
[Unit]
Description=Schedule up-to-date packages

[Timer]
OnBootSec=15min
OnCalendar=Tue,Thu,Sat 01:17

[Install]
WantedBy=multi-user.target
EOF

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
        root /srv/http;
        location / {
            try_files \$uri \$uri/ =404;
            autoindex on;
        }
    }

    # MIME
    include mime.types;
    default_type application/octet-stream;

    # logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    # load configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

tee -a /etc/fstab <<EOF

overlay /srv/http overlay noauto,x-systemd.automount,lowerdir=/var/cache/yum/mirror:/var/empty 0 0
EOF

systemctl enable nginx.service yumsync.timer

ufw disable
ufw allow log 8080/tcp comment 'allow localmirror'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
