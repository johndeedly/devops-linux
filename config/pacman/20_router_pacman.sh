#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed net-tools syslinux dnsmasq iptraf-ng ntp step-ca step-cli darkhttpd nfs-utils \
  samba nbd open-iscsi targetcli-fb python-rtslib-fb python-configshell-fb nvmetcli firewalld

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
  "dhcp-range=::1,::ffff,constructor:lan0,ra-names,64,12h\n"
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

# eth0 is bridged to macvlan device wan0
tee /etc/systemd/network/15-eth0.network <<EOF
[Match]
Name=eth0

[Network]
MACVLAN=wan0
LinkLocalAddressing=no
LLDP=no
EmitLLDP=no
IPv6AcceptRA=no
IPv6SendRA=no
EOF

# eth1 is bridged to macvlan device lan0
tee /etc/systemd/network/15-eth1.network <<EOF
[Match]
Name=eth1

[Network]
MACVLAN=lan0
LinkLocalAddressing=no
LLDP=no
EmitLLDP=no
IPv6AcceptRA=no
IPv6SendRA=no
EOF

# define virtual devices
tee /etc/systemd/network/20-wan0-bridge.netdev <<EOF
[NetDev]
Name=wan0
Kind=macvlan

[MACVLAN]
Mode=private
EOF
tee /etc/systemd/network/20-lan0-bridge.netdev <<EOF
[NetDev]
Name=lan0
Kind=macvlan

[MACVLAN]
Mode=private
EOF

# configure wan0 and lan0
tee /etc/systemd/network/25-wan0.network <<EOF
[Match]
Name=wan0

[Network]
DHCP=yes
MulticastDNS=yes
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
IPv4Forwarding=yes
IPv6Forwarding=yes
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
tee /etc/systemd/network/25-lan0.network <<EOF
[Match]
Name=lan0

[Network]
Address=172.26.0.1/15
Address=fdd5:a799:9326:171d::1/64
EOF

# configure dnsmasq
sed -i '0,/^#\?bind-interfaces.*/s//bind-interfaces/' /etc/dnsmasq.conf
sed -i '0,/^#\?except-interface=.*/s//except-interface=eth0\nexcept-interface=wan0/' /etc/dnsmasq.conf
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

# configure tftp
mkdir -p /srv/tftp/{,bios,efi32,efi64}/pxelinux.cfg
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/syslinux/bios/ /srv/tftp/bios/
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/syslinux/efi32/ /srv/tftp/efi32/
rsync -av --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r /usr/lib/syslinux/efi64/ /srv/tftp/efi64/
tee /srv/tftp/pxelinux.cfg/default <<EOF
$(</cidata/install/pxe/pxelinux.cfg.default)
EOF
ln -s /srv/tftp/pxelinux.cfg/default /srv/tftp/bios/pxelinux.cfg/default
ln -s /srv/tftp/pxelinux.cfg/default /srv/tftp/efi32/pxelinux.cfg/default
ln -s /srv/tftp/pxelinux.cfg/default /srv/tftp/efi64/pxelinux.cfg/default

# configure http
mkdir -p /srv/pxe/arch/x86_64
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
mkdir -p /etc/target
tee /etc/target/saveconfig.json <<'EOF'
{
  "fabric_modules": [],
  "storage_objects": [
    {
      "aio": false,
      "alua_tpgs": [
        {
          "alua_access_state": 0,
          "alua_access_status": 0,
          "alua_access_type": 3,
          "alua_support_active_nonoptimized": 1,
          "alua_support_active_optimized": 1,
          "alua_support_offline": 1,
          "alua_support_standby": 1,
          "alua_support_transitioning": 1,
          "alua_support_unavailable": 1,
          "alua_write_metadata": 0,
          "implicit_trans_secs": 0,
          "name": "default_tg_pt_gp",
          "nonop_delay_msecs": 100,
          "preferred": 0,
          "tg_pt_gp_id": 0,
          "trans_delay_msecs": 0
        }
      ],
      "attributes": {
        "alua_support": 1,
        "block_size": 512,
        "emulate_3pc": 1,
        "emulate_caw": 1,
        "emulate_dpo": 1,
        "emulate_fua_read": 1,
        "emulate_fua_write": 1,
        "emulate_model_alias": 1,
        "emulate_pr": 1,
        "emulate_rest_reord": 0,
        "emulate_rsoc": 1,
        "emulate_tas": 1,
        "emulate_tpu": 0,
        "emulate_tpws": 0,
        "emulate_ua_intlck_ctrl": 0,
        "emulate_write_cache": 0,
        "enforce_pr_isids": 1,
        "force_pr_aptpl": 0,
        "is_nonrot": 0,
        "max_unmap_block_desc_count": 1,
        "max_unmap_lba_count": 8192,
        "max_write_same_len": 4096,
        "optimal_sectors": 16384,
        "pgr_support": 1,
        "pi_prot_format": 0,
        "pi_prot_type": 0,
        "pi_prot_verify": 0,
        "queue_depth": 128,
        "submit_type": 0,
        "unmap_granularity": 1,
        "unmap_granularity_alignment": 0,
        "unmap_zeroes_data": 0
      },
      "dev": "/srv/pxe/arch/x86_64/pxeboot.img",
      "name": "arch",
      "size": 0,
      "plugin": "fileio",
      "write_back": false,
      "wwn": "ea54b27a-7e2a-45c5-af31-933aa92c0bd1"
    }
  ],
  "targets": [
    {
      "fabric": "iscsi",
      "parameters": {
        "cmd_completion_affinity": "-1"
      },
      "tpgs": [
        {
          "attributes": {
            "authentication": 0,
            "cache_dynamic_acls": 0,
            "default_cmdsn_depth": 64,
            "default_erl": 0,
            "demo_mode_discovery": 1,
            "demo_mode_write_protect": 1,
            "fabric_prot_type": 0,
            "generate_node_acls": 0,
            "login_keys_workaround": 1,
            "login_timeout": 15,
            "prod_mode_write_protect": 0,
            "t10_pi": 0,
            "tpg_enabled_sendtargets": 1
          },
          "enable": true,
          "luns": [
            {
              "alias": "07ada4b602",
              "alua_tg_pt_gp_name": "default_tg_pt_gp",
              "index": 0,
              "storage_object": "/backstores/fileio/arch"
            }
          ],
          "node_acls": [
            {
              "attributes": {
                "authentication": 0,
                "dataout_timeout": 3,
                "dataout_timeout_retries": 5,
                "default_erl": 0,
                "nopin_response_timeout": 30,
                "nopin_timeout": 15,
                "random_datain_pdu_offsets": 0,
                "random_datain_seq_offsets": 0,
                "random_r2t_offsets": 0
              },
              "mapped_luns": [
                {
                  "alias": "81aa23cf49",
                  "index": 0,
                  "tpg_lun": 0,
                  "write_protect": true
                }
              ],
              "node_wwn": "iqn.2018-12.internal.pxe:client"
            }
          ],
          "parameters": {
            "AuthMethod": "CHAP,None",
            "DataDigest": "CRC32C,None",
            "DataPDUInOrder": "Yes",
            "DataSequenceInOrder": "Yes",
            "DefaultTime2Retain": "20",
            "DefaultTime2Wait": "2",
            "ErrorRecoveryLevel": "0",
            "FirstBurstLength": "65536",
            "HeaderDigest": "CRC32C,None",
            "IFMarkInt": "Reject",
            "IFMarker": "No",
            "ImmediateData": "Yes",
            "InitialR2T": "Yes",
            "MaxBurstLength": "262144",
            "MaxConnections": "1",
            "MaxOutstandingR2T": "1",
            "MaxRecvDataSegmentLength": "8192",
            "MaxXmitDataSegmentLength": "262144",
            "OFMarkInt": "Reject",
            "OFMarker": "No",
            "TargetAlias": "LIO Target"
          },
          "portals": [
            {
              "ip_address": "[::]",
              "iser": false,
              "offload": false,
              "port": 3260
            }
          ],
          "tag": 1
        }
      ],
      "wwn": "iqn.2018-12.internal.pxe:arch"
    }
  ]
}
EOF
tee /usr/local/bin/update-arch-target.sh <<'EOF'
#!/usr/bin/env bash

CONFIG_PATH=$(jq -r '.storage_objects[] | select(.name == "arch") | .dev' /etc/target/saveconfig.json)
if [ -f "$CONFIG_PATH" ]; then
  CONFIG_SIZE=$(wc -c <"$CONFIG_PATH")
  jq --arg newsize "$CONFIG_SIZE" '(.storage_objects[] | select(.name == "arch")).size |= ($newsize|tonumber)' /etc/target/saveconfig.json | sponge /etc/target/saveconfig.json
fi
EOF
chmod +x /usr/local/bin/update-arch-target.sh
tee /etc/systemd/system/update-arch-target.service <<EOF
[Unit]
Description=Update size of pxe boot arch target
Before=target.service

[Service]
Type=simple
StandardInput=null
StandardOutput=journal
StandardError=journal
ExecStart=/usr/local/bin/update-arch-target.sh

[Install]
WantedBy=multi-user.target
EOF
sed -e 's/^node.conn[0].timeo.noop_out_interval.*/node.conn[0].timeo.noop_out_interval = 0/' \
    -e 's/^node.conn[0].timeo.noop_out_timeout.*/node.conn[0].timeo.noop_out_timeout = 0/' \
    -e 's/^node.session.timeo.replacement_timeout.*/node.session.timeo.replacement_timeout = 86400/' -i /etc/iscsi/iscsid.conf
tee /etc/udev/rules.d/50-iscsi.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="scsi" , ATTR{type}=="0|7|14", RUN+="/bin/sh -c 'echo Y > /sys$$DEVPATH/timeout'"
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
  target update-arch-target smb nbd nvmet

# configure the firewall
firewall-offline-cmd --zone=public --add-service=dhcp
firewall-offline-cmd --zone=public --add-service=proxy-dhcp
firewall-offline-cmd --zone=public --add-service=dhcpv6
firewall-offline-cmd --zone=public --add-service=dns
firewall-offline-cmd --zone=public --add-service=ntp
firewall-offline-cmd --zone=public --add-service=tftp
firewall-offline-cmd --zone=public --add-service=http
firewall-offline-cmd --zone=public --add-port=8443/tcp
firewall-offline-cmd --zone=public --add-service=nfs
firewall-offline-cmd --zone=public --add-service=rpc-bind
firewall-offline-cmd --zone=public --add-service=mountd
firewall-offline-cmd --zone=public --add-port=32767/tcp
firewall-offline-cmd --zone=public --add-port=32767/udp
firewall-offline-cmd --zone=public --add-port=32765/tcp
firewall-offline-cmd --zone=public --add-port=32765/udp
firewall-offline-cmd --zone=public --add-service=iscsi-target
firewall-offline-cmd --zone=public --add-service=samba
firewall-offline-cmd --zone=public --add-port=10809/tcp
firewall-offline-cmd --zone=public --add-port=8009/tcp

# disable network config in cloud init
tee /etc/cloud/cloud.cfg.d/99-custom-networking.cfg <<EOF
network:
  config: disabled
disable_network_activation: true
EOF
find /etc/systemd/network -name "05-wired.network" -print -delete
find /etc/systemd/network -name "10-cloud-init*.network" -print -delete
