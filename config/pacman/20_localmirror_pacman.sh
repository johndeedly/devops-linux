#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed expac nginx pacman-contrib

# prepare mirror cache dir
mkdir -p /var/cache/pacman/mirror

# restore default mirror
tee /etc/pacman.d/mirrorlist <<'EOF'
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
EOF
LC_ALL=C yes | LC_ALL=C pacman -Sy --noconfirm
LC_ALL=C yes | LC_ALL=C pacman -Fy --noconfirm

tee /usr/local/bin/pacsync.sh <<'EOF'
#!/usr/bin/env bash

if [ -f /var/lib/pacman/db.lck ]; then
    killall -SIGINT pacman
    rm /var/lib/pacman/db.lck || true
fi

/usr/bin/pacman -Sy --noconfirm
/usr/bin/pacman -Fy --noconfirm
rm /var/tmp/mirror_url_list.txt /var/tmp/mirror_file_list.txt

while read -r repo; do
    mkdir -p "/var/cache/pacman/mirror/geo.mirror.pkgbuild.com/$repo/os/x86_64"
    ln -s "/var/lib/pacman/sync/$repo.db" "/var/cache/pacman/mirror/geo.mirror.pkgbuild.com/$repo/os/x86_64/$repo.db" || true
    ln -s "/var/lib/pacman/sync/$repo.files" "/var/cache/pacman/mirror/geo.mirror.pkgbuild.com/$repo/os/x86_64/$repo.files" || true
    /usr/bin/expac -Ss '%r/%n' | grep "^$repo/" | xargs pacman -Swddp --logfile "/dev/null" --cachedir "/dev/null" | while read -r line; do
      echo "$line"
      echo "$line".sig
    done >> /var/tmp/mirror_url_list.txt
done <<EOX
core
extra
multilib
EOX

tmpdir=$(mktemp -d)
wget -c -N -P "${tmpdir}" --progress=dot https://geo.mirror.pkgbuild.com/iso/latest/arch/version
if [ -f "${tmpdir}/version" ]; then
  ISO_BASE=$(<"${tmpdir}/version")
else
  ISO_BASE=$(date +%Y.%m.01)
fi
rm -r "${tmpdir}"

tee -a /var/tmp/mirror_url_list.txt <<EOS
https://archive.archlinux.org/iso/${ISO_BASE}/archlinux-x86_64.iso
https://archive.archlinux.org/iso/${ISO_BASE}/archlinux-x86_64.iso.sig
https://archive.archlinux.org/iso/${ISO_BASE}/arch/boot/x86_64/initramfs-linux.img
https://archive.archlinux.org/iso/${ISO_BASE}/arch/boot/x86_64/initramfs-linux.img.ipxe.sig
https://archive.archlinux.org/iso/${ISO_BASE}/arch/boot/x86_64/vmlinuz-linux
https://archive.archlinux.org/iso/${ISO_BASE}/arch/boot/x86_64/vmlinuz-linux.ipxe.sig
https://archive.archlinux.org/iso/${ISO_BASE}/arch/x86_64/airootfs.sfs
https://archive.archlinux.org/iso/${ISO_BASE}/arch/x86_64/airootfs.sfs.cms.sig
https://archive.archlinux.org/iso/${ISO_BASE}/arch/x86_64/airootfs.sha512
EOS

tee -a /var/tmp/mirror_url_list.txt <<EOS
https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-basic.qcow2
https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-basic.qcow2.SHA256
https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-basic.qcow2.sig
https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2.SHA256
https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2.sig
EOS

# sort the uri list for faster download
LC_ALL=C sort -u -o /var/tmp/mirror_url_list_sorted.txt /var/tmp/mirror_url_list.txt && \
  mv /var/tmp/mirror_url_list_sorted.txt /var/tmp/mirror_url_list.txt

# convert the filelist to a local filelist for later
python3 -c 'import sys, urllib.parse as p; [ print(p.unquote(l.rstrip())) for l in sys.stdin ]' </var/tmp/mirror_url_list.txt | \
  sed -e 's|^https\?://|/var/cache/pacman/mirror/|g' >> /var/tmp/mirror_file_list.txt

split -n l/4 /var/tmp/mirror_url_list.txt /var/tmp/mirror_url_part_
i=0
for part in /var/tmp/mirror_url_part_*; do
  # force paths on downloaded files, continue unfinished downloads and skip already downloaded ones, use timestamps,
  # download to target path, load download list from file, force progress bar when executed in tty and skip otherwise
  systemd-cat -t "wget_part_$i" wget -x -c -N -P /var/cache/pacman/mirror -i "$part" --progress=bar:force:noscroll &
  ((i++))
done
wait

rm /var/tmp/mirror_url_list.txt /var/tmp/mirror_url_part_*

# remove unneeded files
# grep: interpret pattern as a list of fixed strings, separated by newlines, select only those matches that exactly match the whole line,
# invert the sense of matching, to select non-matching lines, obtain patterns from file, one per line
find /var/cache/pacman/mirror -type f -printf '%p\n' | grep --fixed-strings --line-regexp --invert-match --file=/var/tmp/mirror_file_list.txt | while read -r line; do
  echo "removing $line"
  rm "$line"
done

rm /var/tmp/mirror_file_list.txt
EOF
chmod +x /usr/local/bin/pacsync.sh

tee /etc/systemd/system/pacsync.service <<'EOF'
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
WorkingDirectory=/var/cache/pacman
ExecStart=/usr/local/bin/pacsync.sh
EOF

tee /etc/systemd/system/pacsync.timer <<EOF
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
        root /var/cache/pacman/mirror;
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

systemctl enable nginx.service pacsync.timer

# enable pkgmirror mDNS advertising
tee /etc/systemd/dnssd/pkgmirror.dnssd <<EOF
[Service]
Name=%H
Type=_pkgmirror._tcp
SubType=_arch
Port=8080
EOF

ufw disable
ufw allow log 8080/tcp comment 'allow localmirror'
ufw enable
ufw status verbose

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
