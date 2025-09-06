#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed net-tools syslinux dnsmasq iptraf-ng ntp step-ca step-cli darkhttpd nfs-utils \
  samba nbd tgt nvmetcli rsync

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
  "dhcp-range=::1,::ffff,constructor:eth1,ra-names,64,12h\n"
)

DNS_SERVERS=(
  "server=94.140.14.14@eth0\n"
  "server=94.140.15.15@eth0\n"
  "server=2a10:50c0::ad1:ff@eth0\n"
  "server=2a10:50c0::ad2:ff@eth0"
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
tee /etc/systemd/network/05-all-keep-names.link <<EOF
[Match]
OriginalName=*

[Link]
NamePolicy=keep
EOF

# configure eth0
tee /etc/systemd/network/05-eth0.network <<EOF
[Match]
Name=eth0

[Network]
DHCP=yes
MulticastDNS=yes
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
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
tee /etc/systemd/network/05-eth1.network <<EOF
[Match]
Name=eth1

[Link]
RequiredForOnline=no

[Network]
Address=172.26.0.1/15
Address=fdd5:a799:9326:171d::1/64
EOF

# configure dnsmasq
sed -i '0,/^#\?bind-interfaces.*/s//bind-interfaces/' /etc/dnsmasq.conf
sed -i '0,/^#\?interface=.*/s//interface=eth1/' /etc/dnsmasq.conf
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
sed -i '0,/^#\?server=.*/s//'"${DNS_SERVERS[*]}"'/' /etc/dnsmasq.conf

# configure pxe folders
mkdir -p /srv/pxe/{arch,debian,ubuntu}/x86_64

# configure tftp
mkdir -p /srv/tftp/{,bios,efi32,efi64}/pxelinux.cfg
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/syslinux/bios/ /srv/tftp/bios/
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/syslinux/efi32/ /srv/tftp/efi32/
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/syslinux/efi64/ /srv/tftp/efi64/
tee /srv/tftp/pxelinux.cfg/default <<EOF
$(</var/lib/cloud/instance/provision/pacman/20_router_pacman/pxelinux.cfg.default)
EOF
ln -s /srv/tftp/pxelinux.cfg/default /srv/tftp/bios/pxelinux.cfg/default
ln -s /srv/tftp/pxelinux.cfg/default /srv/tftp/efi32/pxelinux.cfg/default
ln -s /srv/tftp/pxelinux.cfg/default /srv/tftp/efi64/pxelinux.cfg/default

# configure http
mkdir -p /etc/systemd/system/darkhttpd.service.d
tee /etc/systemd/system/darkhttpd.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/darkhttpd /srv/pxe --ipv6 --addr '::' --port 80 --mimetypes /etc/conf.d/mimetypes
EOF
systemctl enable darkhttpd.service

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

# the router is it's own acme protocol certificate authority
useradd -d /srv/step step
install -d -m 0755 -o step -g step /srv/step
install -d -m 0755 -o step -g step /srv/step/.step
install -d -m 0755 -o step -g step /var/log/step-ca
tee /etc/systemd/system/step-ca.service <<EOF
[Unit]
Description=step-ca
After=syslog.target network.target

[Service]
User=step
Group=step
StandardInput=null
StandardOutput=journal
StandardError=journal
ExecStart=/bin/sh -c '/bin/step-ca /srv/step/.step/config/ca.json --password-file=/srv/step/.step/pwd'
Type=simple
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

openssl rand -base64 36 | tee /srv/step/.step/pwd
chown step:step /srv/step/.step/pwd
chmod 400 /srv/step/.step/pwd

su -s /bin/bash - step <<EOS
step-cli ca init --deployment-type=standalone --name=internal --dns=172.26.0.1 --dns=fdd5:a799:9326:171d::1 --dns=172.28.0.1 --dns=fd97:6274:3c67:7974::1 --dns=router.internal --dns=gateway.internal --address=:8443 --provisioner=step-ca@router.internal --password-file=/srv/step/.step/pwd --acme --ssh
sed -i '0,/"name": "acme".*/s//"name": "acme",\n\t\t\t\t"claims": {\n\t\t\t\t\t"maxTLSCertDuration": "2160h",\n\t\t\t\t\t"defaultTLSCertDuration": "2160h"\n\t\t\t\t}/' /srv/step/.step/config/ca.json
EOS

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
# https://www.baeldung.com/linux/firewalld-nfs-connections-settings
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

# configure nvmeof
mkdir -p /etc/nvmet
tee /etc/nvmet/config.json <<'EOF'
{
  "hosts": [
    {
      "nqn": "hostnqn"
    }
  ],
  "ports": [
    {
      "addr": {
        "adrfam": "ipv6",
        "traddr": "::",
        "treq": "not specified",
        "trsvcid": "8009",
        "trtype": "tcp",
        "tsas": "none"
      },
      "ana_groups": [
        {
          "ana": {
            "state": "optimized"
          },
          "grpid": 1
        }
      ],
      "param": {
        "inline_data_size": "16384",
        "pi_enable": "0"
      },
      "portid": 1,
      "referrals": [],
      "subsystems": [
        "testnqn"
      ]
    }
  ],
  "subsystems": [
    {
      "allowed_hosts": [],
      "attr": {
        "allow_any_host": "1",
        "cntlid_max": "65519",
        "cntlid_min": "1",
        "firmware": "6.7.9-ar",
        "ieee_oui": "0x000000",
        "model": "Linux",
        "pi_enable": "0",
        "qid_max": "128",
        "serial": "d958dba9aa7f964f3163",
        "version": "1.3"
      },
      "namespaces": [
        {
          "ana": {
            "grpid": "1"
          },
          "ana_grpid": 1,
          "device": {
            "nguid": "00000000-0000-0000-0000-000000000000",
            "path": "/srv/pxe/arch/x86_64/pxeboot.img",
            "uuid": "43c4260a-826b-475d-9b42-883b4258f53f"
          },
          "enable": 1,
          "nsid": 1
        }
      ],
      "nqn": "testnqn"
    }
  ]
}
EOF
tee /etc/modules-load.d/nvmet.conf <<EOF
nvmet
EOF

# Enable all configured services
systemctl enable dnsmasq ntpd.timer step-ca hosts-calc nfsv4-server rpc-statd \
  tgtd smb nbd nvmet

# configure the firewall
ufw disable

# ==========
# eth0 - extern
# ==========
ufw allow in on eth0 to any port 51820 comment 'allow wireguard on extern'

# ==========
# eth1 - intern
# ==========
ufw allow in on eth1 to any port bootps comment 'allow bootps on intern'
ufw allow in on eth1 to any port 53 comment 'allow dns on intern'
ufw allow in on eth1 to any port 67 proto udp comment 'allow dhcpv4 server'
ufw allow in on eth1 to any port 547 proto udp comment 'allow dhcpv6 server'
ufw allow in on eth1 to any port tftp comment 'allow tftp on intern'
ufw allow in on eth1 to any port 80 comment 'allow http on intern'
ufw allow in on eth1 to any port ntp comment 'allow ntp on intern'
ufw allow in on eth1 to any port 111 comment 'allow nfs on intern'
ufw allow in on eth1 to any port 2049 comment 'allow nfs on intern'
ufw allow in on eth1 to any port 20048 comment 'allow nfs on intern'
ufw allow in on eth1 to any port 32767 comment 'allow nfs on intern'
ufw allow in on eth1 to any port 32765 comment 'allow nfs on intern'
ufw allow in on eth1 to any port nbd comment 'allow nbd on intern'
ufw allow in on eth1 to any port 445 comment 'allow cifs on intern'
ufw allow in on eth1 to any port 139 comment 'allow cifs on intern'
ufw allow in on eth1 to any port 3260 proto tcp comment 'allow iscsi on intern'
ufw allow in on eth1 to any port 8009 proto tcp comment 'allow nvmet on intern'
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

# before.rules
tee -a /etc/ufw/before.rules <<EOF

*nat
:PREROUTING ACCEPT [0:0]
-A PREROUTING -i eth1 -p udp --dport 53 -j DNAT --to-destination 172.26.0.1:53
-A PREROUTING -i eth1 -p tcp --dport 53 -j DNAT --to-destination 172.26.0.1:53
-A PREROUTING -i eth1 -p tcp --dport 853 -j DNAT --to-destination 172.26.0.1:853

:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 172.26.0.0/15 -o eth0 -j MASQUERADE

COMMIT
EOF
tee -a /etc/ufw/before6.rules <<EOF

*nat
:PREROUTING ACCEPT [0:0]
-A PREROUTING -i eth1 -p udp --dport 53 -j DNAT --to-destination [fdd5:a799:9326:171d::1]:53
-A PREROUTING -i eth1 -p tcp --dport 53 -j DNAT --to-destination [fdd5:a799:9326:171d::1]:53
-A PREROUTING -i eth1 -p tcp --dport 853 -j DNAT --to-destination [fdd5:a799:9326:171d::1]:853

:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s fdd5:a799:9326:171d::/64 -o eth0 -j MASQUERADE

COMMIT
EOF

ufw enable
ufw status verbose

# enable ip forwarding in kernel
tee -a /etc/ufw/sysctl.conf <<EOF
net/ipv4/ip_forward=1
net/ipv6/conf/default/forwarding=1
net/ipv6/conf/all/forwarding=1
EOF

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
[ -f "${0}" ] && rm -- "${0}"
