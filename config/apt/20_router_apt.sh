#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install net-tools syslinux syslinux-efi pxelinux dnsmasq iptraf-ng \
  ntp nginx nfs-kernel-server portmap nfs-common samba nbd-server tgt rsync

DHCP_ADDITIONAL_SETUP=(
  "dhcp-option=option:dns-server,172.26.0.1\n"
  "dhcp-option=option6:dns-server,[fdd5:a799:9326:171d::1]\n"
  "dhcp-option=option:ntp-server,172.26.0.1\n"
  "dhcp-option=option6:ntp-server,[fdd5:a799:9326:171d::1]\n"
  "\n"
  "# Override the default route supplied by dnsmasq, which assumes the"
)

DHCP_RANGES=(
  "dhcp-range=172.27.0.1,172.27.255.254,255.254.0.0,12h\n"
  "dhcp-range=::1,::ffff,constructor:br0,ra-names,64,12h\n"
)

PXESETUP=(
  "dhcp-match=set:efi-x86_64,option:client-arch,7\n"
  "dhcp-match=set:efi-x86_64,option:client-arch,9\n"
  "dhcp-match=set:efi-x86,option:client-arch,6\n"
  "dhcp-match=set:bios,option:client-arch,0\n"

  "dhcp-boot=tag:efi-x86_64,efi64\/syslinux.efi\n"
  "dhcp-boot=tag:efi-x86,efi32\/syslinux.efi\n"
  "dhcp-boot=tag:bios,bios\/lpxelinux.0"
)

DHCP_209_SETUP=(
  "dhcp-option-force=tag:efi-x86_64,209,pxelinux.cfg\/default\n"
  "dhcp-option-force=tag:efi-x86,209,pxelinux.cfg\/default\n"
  "dhcp-option-force=tag:bios,209,pxelinux.cfg\/default"
)

DHCP_210_SETUP=(
  "dhcp-option-force=tag:efi-x86_64,210,efi64\/\n"
  "dhcp-option-force=tag:efi-x86,210,efi32\/\n"
  "dhcp-option-force=tag:bios,210,bios\/"
)

# keep all interface names
tee /etc/systemd/network/10-all-keep-names.link <<EOF
[Match]
OriginalName=*

[Link]
NamePolicy=keep
EOF

# configure eth0
tee /etc/systemd/network/15-eth0.network <<EOF
[Match]
Name=eth0

[Network]
DHCP=yes
MulticastDNS=yes
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
IPForward=yes
IPMasquerade=both

[DHCPv4]
RouteMetric=10

[IPv6AcceptRA]
RouteMetric=10

[DHCPPrefixDelegation]
RouteMetric=10

[IPv6Prefix]
RouteMetric=10
EOF

# configure eth1
tee /etc/systemd/network/15-eth1.network <<EOF
[Match]
Name=eth1

[Link]
RequiredForOnline=no

[Network]
Bridge=br0
EOF

# configure br0
tee /etc/systemd/network/15-br0.netdev <<EOF
[NetDev]
Name=br0
Kind=bridge
EOF
tee /etc/systemd/network/25-br0.network <<EOF
[Match]
Name=br0

[Link]
RequiredForOnline=no

[Network]
Address=172.26.0.1/15
Address=fdd5:a799:9326:171d::1/64
EOF

# configure dnsmasq
sed -i '0,/^#\?bind-interfaces.*/s//bind-interfaces/' /etc/dnsmasq.conf
sed -i '0,/^#\?except-interface=.*/s//except-interface=eth0\nexcept-interface=eth0/' /etc/dnsmasq.conf
sed -i '0,/^#\?domain-needed.*/s//domain-needed/' /etc/dnsmasq.conf
sed -i '0,/^#\?bogus-priv.*/s//bogus-priv/' /etc/dnsmasq.conf
sed -i '0,/^#\?local=.*/s//local=\/internal\//' /etc/dnsmasq.conf
sed -i '0,/^#\?domain=.*/s//domain=internal/' /etc/dnsmasq.conf
sed -i '0,/^#\?dhcp-range=.*/s//'"${DHCP_RANGES[*]}"'/' /etc/dnsmasq.conf
sed -i '0,/^# Override the default route.*/s//'"${DHCP_ADDITIONAL_SETUP[*]}"'/' /etc/dnsmasq.conf
sed -i '0,/^#\?enable-ra.*/s//enable-ra/' /etc/dnsmasq.conf
sed -i '0,/^#\?enable-tftp.*/s//enable-tftp/' /etc/dnsmasq.conf
sed -i '0,/^#\?tftp-root=.*/s//tftp-root=\/srv\/tftp/' /etc/dnsmasq.conf
sed -i '0,/^#\?log-dhcp.*/s//log-dhcp/' /etc/dnsmasq.conf
sed -i '0,/^#\?log-queries.*/s//log-queries/' /etc/dnsmasq.conf
sed -i '0,/^#\?dhcp-boot=.*/s//'"${PXESETUP[*]}"'/' /etc/dnsmasq.conf
sed -i '0,/^#\?dhcp-option-force=209.*/s//'"${DHCP_209_SETUP[*]}"'/' /etc/dnsmasq.conf
sed -i '0,/^#\?dhcp-option-force=210.*/s//'"${DHCP_210_SETUP[*]}"'/' /etc/dnsmasq.conf

# configure pxe folders
mkdir -p /srv/pxe/{arch,debian,ubuntu}/x86_64

# configure tftp
mkdir -p /srv/tftp/{,bios,efi32,efi64}/pxelinux.cfg
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/syslinux/modules/bios/ /srv/tftp/bios/
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/PXELINUX/ /srv/tftp/bios/
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/syslinux/modules/efi32/ /srv/tftp/efi32/
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/SYSLINUX.EFI/efi32/ /srv/tftp/efi32/
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/syslinux/modules/efi64/ /srv/tftp/efi64/
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/SYSLINUX.EFI/efi64/ /srv/tftp/efi64/
tee /srv/tftp/pxelinux.cfg/default <<EOF
$(</var/lib/cloud/instance/provision/apt/20_router_apt/pxelinux.cfg.default)
EOF
ln -s /srv/tftp/pxelinux.cfg/default /srv/tftp/bios/pxelinux.cfg/default
ln -s /srv/tftp/pxelinux.cfg/default /srv/tftp/efi32/pxelinux.cfg/default
ln -s /srv/tftp/pxelinux.cfg/default /srv/tftp/efi64/pxelinux.cfg/default

# configure http
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
        listen 80;
        listen [::]:80;
        server_name $(cat /etc/hostname);
        root /srv/pxe;
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
rm /etc/nginx/sites-enabled/default
systemctl enable nginx.service

# configure ntp
tee /etc/ntp.conf <<EOF
server 0.de.pool.ntp.org iburst
server 1.de.pool.ntp.org iburst
server 2.de.pool.ntp.org iburst
server 3.de.pool.ntp.org iburst
tos orphan 15

restrict default kod limited nomodify notrap nopeer noquery
restrict -6 default kod limited nomodify notrap nopeer noquery

restrict 127.0.0.1
restrict -6 ::1  

driftfile /var/lib/ntp/ntp.drift
logfile /var/log/ntp.log
EOF
tee /etc/systemd/system/ntpd.timer <<EOF
[Timer]
OnBootSec=30

[Install]
WantedBy=multi-user.target
EOF
mkdir -p /etc/systemd/system/ntpd.service.d
tee /etc/systemd/system/ntpd.service.d/override.conf <<EOF
[Service]
Restart=on-failure
RestartSec=23
EOF

# configure iscsi
tee /etc/tgt/targets.conf <<EOF
<target iqn.2018-12.internal.pxe:target>
  backing-store /srv/pxe/arch/x86_64/pxeboot.img
  allow-in-use on
  readonly on
</target>
EOF

# update hosts file on startup
tee /usr/local/bin/hosts-calc <<'EOS'
#!/usr/bin/env bash

# Set hostname in etc/hosts
FQDNAME=$(cat /etc/hostname)
HOSTNAME=${FQDNAME%%.*}
tee /tmp/hosts_columns <<EOF
# IPv4/v6|FQDN|HOSTNAME
EOF
ip -f inet addr | awk '/inet / {print $2}' | cut -d'/' -f1 | while read -r PUB_IP_ADDR; do
tee -a /tmp/hosts_columns <<EOF
$PUB_IP_ADDR|$FQDNAME|$HOSTNAME
$PUB_IP_ADDR|router.internal|router
$PUB_IP_ADDR|gateway.internal|gateway
EOF
done
ip -f inet6 addr | awk '/inet6 / {print $2}' | cut -d'/' -f1 | while read -r PUB_IP_ADDR; do
tee -a /tmp/hosts_columns <<EOF
$PUB_IP_ADDR|$FQDNAME|$HOSTNAME
$PUB_IP_ADDR|router.internal|router
$PUB_IP_ADDR|gateway.internal|gateway
EOF
done
tee /etc/hosts <<EOF
# Static table lookup for hostnames.
# See hosts(5) for details.

# https://www.icann.org/en/public-comment/proceeding/proposed-top-level-domain-string-for-private-use-24-01-2024
$(column /tmp/hosts_columns -t -s '|')
EOF
rm /tmp/hosts_columns
EOS
chmod +x /usr/local/bin/hosts-calc
tee /etc/systemd/system/hosts-calc.service <<EOF
[Unit]
Description=Generate hosts file on startup
Wants=network.target
After=network.target

[Service]
ExecStartPre=/usr/lib/systemd/systemd-networkd-wait-online --operational-state=routable --any
ExecStart=/usr/local/bin/hosts-calc

[Install]
WantedBy=multi-user.target
EOF

# configure nfs
# https://www.baeldung.com/linux/ufw-nfs-connections-settings
mkdir -p /srv/pxe/arch/x86_64
sed -i '0,/^\[mountd\].*/s//[mountd]\nport=20048/' /etc/nfs.conf
sed -i '0,/^\[lockd\].*/s//[lockd]\nport=32767\nudp-port=32767/' /etc/nfs.conf
sed -i '0,/^\[statd\].*/s//[statd]\nport=32765/' /etc/nfs.conf
sed -i '0,/^\[nfsd\].*/s//[nfsd]\nthreads=16/' /etc/nfs.conf

tee /etc/exports <<EOF
/srv/pxe    127.0.0.0/8(all_squash,insecure,ro)
/srv/pxe    172.26.0.0/15(all_squash,insecure,ro)
/srv/pxe    ::1/128(all_squash,insecure,ro)
/srv/pxe    fdd5:a799:9326:171d::/64(all_squash,insecure,ro)
EOF

# configure cifs
tee /etc/samba/smb.conf <<EOF
[pxe]
path = /srv/pxe
browseable = yes
read only = yes
guest ok = yes
public = yes
EOF

# configure scp
USERID=pxe
useradd -d /srv/pxe -e "" -f "-1" -N -l "${USERID}"
PXEPWDHASH=$(openssl passwd -6 -salt abcxyz "$USERID")
sed -i 's/^'"$USERID"':[^:]*:/'"$USERID"':'"${PXEPWDHASH//\//\\/}"':/' /etc/shadow

# configure nbd
tee /etc/nbd-server/config <<EOF
[generic]
[pxe]
  readonly = true
  exportname = /srv/pxe/arch/x86_64/pxeboot.img
  authfile = /etc/nbd-server/allow
EOF
tee /etc/nbd-server/allow <<EOF
127.0.0.0/8
172.26.0.0/15
::1/128
fdd5:a799:9326:171d::/64
EOF

# Enable all configured services
systemctl enable dnsmasq ntpd.timer hosts-calc.service nfs-kernel-server rpc-statd \
  tgt smb nbd

# configure the firewall
ufw disable

# remove existing ssh rule
ufw delete allow log ssh

# ==========
# eth0 - extern
# ==========
ufw allow in on eth0 proto tcp to any port 51820 comment 'allow wireguard tcp on extern'
ufw allow in on eth0 proto udp to any port 51820 comment 'allow wireguard udp on extern'

# ==========
# eth1 - intern
# ==========
ufw allow in on eth1 to any port bootps comment 'allow bootps on intern'
ufw allow in on eth1 to any port ssh comment 'allow ssh on intern'
ufw allow in on eth1 to any port 53 comment 'allow dns on intern'
ufw allow in on eth1 to any port tftp comment 'allow tftp on intern'
ufw allow in on eth1 to any port 80 comment 'allow http on intern'
ufw allow in on eth1 to any port ntp comment 'allow ntp on intern'
ufw allow in on eth1 to any port 111 comment 'allow nfs on intern'
ufw allow in on eth1 to any port 2049 comment 'allow nfs on intern'
ufw allow in on eth1 to any port 20048 comment 'allow nfs on intern'
ufw allow in on eth1 to any port 32767/tcp comment 'allow nfs on intern'
ufw allow in on eth1 to any port 32767/udp comment 'allow nfs on intern'
ufw allow in on eth1 to any port 32765/tcp comment 'allow nfs on intern'
ufw allow in on eth1 to any port 32765/udp comment 'allow nfs on intern'
ufw allow in on eth1 to any port nbd comment 'allow nbd on intern'
ufw allow in on eth1 to any port 445 comment 'allow cifs on intern'
ufw allow in on eth1 to any port 139 comment 'allow cifs on intern'
ufw allow in on eth1 to any port 3260/tcp comment 'allow iscsi on intern'
ufw allow in on eth1 to any port 51820 comment 'allow wireguard on intern'

ufw route deny in on eth1 out on eth0 to any port 53 comment 'block dns from intern to extern'
ufw route deny in on eth1 out on eth0 to any port 853 comment 'block dns from intern to extern'
ufw route deny in on eth1 out on eth0 to any port 5353 comment 'block dns from intern to extern'
ufw route deny in on wg0 out on eth0 to any port 53 comment 'block dns from wireguard to extern'
ufw route deny in on wg0 out on eth0 to any port 853 comment 'block dns from wireguard to extern'
ufw route deny in on wg0 out on eth0 to any port 5353 comment 'block dns from wireguard to extern'
ufw route allow in on eth1 out on eth0 comment 'allow forward from intern to extern'
ufw route allow in on eth1 out on wg0 comment 'allow forward from intern to wireguard'
ufw route allow in on eth1 out on eth1 comment 'allow local intern forwarding'

# ==========
# wg0 - wireguard
# ==========
ufw route allow in on wg0 out on eth0 comment 'allow forward from wireguard to extern'
ufw route allow in on wg0 out on eth1 comment 'allow forward from wireguard to intern'
ufw route allow in on wg0 out on wg0 comment 'allow local wireguard forwarding'

# ==========
# lo - loopback
# ==========
ufw allow in on lo comment 'allow loopback in'
ufw route allow in on lo out on lo comment 'allow loopback forward'

ufw enable
ufw status verbose

#
# debian/ubuntu only:
#
# disable network renaming in kernel command line
sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=["][^"]*\)/\1 net.ifnames=0/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
if [ -d /boot/efi/EFI/debian ]; then
  grub-mkconfig -o /boot/efi/EFI/debian/grub.cfg
elif [ -d /boot/efi/EFI/ubuntu ]; then
  grub-mkconfig -o /boot/efi/EFI/ubuntu/grub.cfg
fi
# disable netplan completely out of existence
rm -r /etc/netplan/*
LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y remove --purge netplan.io

# disable network config in cloud init
tee /etc/cloud/cloud.cfg.d/99-custom-networking.cfg <<EOF
network:
  config: disabled
disable_network_activation: true
EOF
find /etc/systemd/network -name "05-wired.network" -print -delete
find /etc/systemd/network -name "10-cloud-init*.network" -print -delete

# sync everything to disk
sync

# cleanup
rm -- "${0}"
