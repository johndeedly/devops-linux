#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# Checking logrotate presence
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
    logrotate libpam-tmpdir apt-listbugs needrestart fail2ban cracklib debsums apt-show-versions
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed logrotate fail2ban cracklib
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C dnf install -y logrotate fail2ban cracklib
fi
systemctl enable --now logrotate.timer

# Kernel Hardening
sysctl -w dev.tty.ldisc_autoload=0
sysctl -w fs.protected_fifos=2
sysctl -w fs.protected_hardlinks=1
sysctl -w fs.protected_regular=2
sysctl -w fs.protected_symlinks=1
sysctl -w fs.suid_dumpable=0
sysctl -w kernel.core_uses_pid=1
sysctl -w kernel.ctrl-alt-del=0
sysctl -w kernel.dmesg_restrict=1
sysctl -w kernel.kptr_restrict=2
# Firewall and other software relies on module loading
#sysctl -w kernel.modules_disabled=1
sysctl -w kernel.perf_event_paranoid=3
sysctl -w kernel.randomize_va_space=2
sysctl -w kernel.sysrq=0
sysctl -w kernel.unprivileged_bpf_disabled=1
sysctl -w kernel.yama.ptrace_scope=1
sysctl -w net.core.bpf_jit_harden=2
sysctl -w net.ipv4.conf.all.accept_redirects=0
sysctl -w net.ipv4.conf.all.accept_source_route=0
sysctl -w net.ipv4.conf.all.bootp_relay=0
sysctl -w net.ipv4.conf.all.forwarding=0
sysctl -w net.ipv4.conf.all.log_martians=1
sysctl -w net.ipv4.conf.all.mc_forwarding=0
sysctl -w net.ipv4.conf.all.proxy_arp=0
sysctl -w net.ipv4.conf.all.rp_filter=1
sysctl -w net.ipv4.conf.all.send_redirects=0
sysctl -w net.ipv4.conf.default.accept_redirects=0
sysctl -w net.ipv4.conf.default.accept_source_route=0
sysctl -w net.ipv4.conf.default.log_martians=1
sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1
sysctl -w net.ipv4.icmp_ignore_bogus_error_responses=1
sysctl -w net.ipv4.tcp_syncookies=1
sysctl -w net.ipv4.tcp_timestamps=0 1
sysctl -w net.ipv6.conf.all.accept_redirects=0
sysctl -w net.ipv6.conf.all.accept_source_route=0
sysctl -w net.ipv6.conf.default.accept_redirects=0
sysctl -w net.ipv6.conf.default.accept_source_route=0
tee /etc/sysctl.d/90-hardening.conf <<EOF
dev.tty.ldisc_autoload=0
fs.protected_fifos=2
fs.protected_hardlinks=1
fs.protected_regular=2
fs.protected_symlinks=1
fs.suid_dumpable=0
kernel.core_uses_pid=1
kernel.ctrl-alt-del=0
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
# Firewall and other software relies on module loading
#kernel.modules_disabled=1
kernel.perf_event_paranoid=2
kernel.randomize_va_space=2
kernel.sysrq=0
kernel.unprivileged_bpf_disabled=1
kernel.yama.ptrace_scope=1
net.core.bpf_jit_harden=2
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.all.bootp_relay=0
net.ipv4.conf.all.forwarding=0
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.all.mc_forwarding=0
net.ipv4.conf.all.proxy_arp=0
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.default.log_martians=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_timestamps=0 1
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.default.accept_redirects=0
net.ipv6.conf.default.accept_source_route=0
EOF

# sshd hardening SSH-7408
sshdmod() {
if ! [ -f /etc/ssh/sshd_config ]; then
  touch /etc/ssh/sshd_config
fi

if grep -q "$1" /etc/ssh/sshd_config; then
  echo "[ ## ] change $1 to $2 in /etc/ssh/sshd_config"
  sed -i "s/$1.*/$1 $2/g" /etc/ssh/sshd_config
else
  echo "[ ## ] add $1 $2 to /etc/ssh/sshd_config"
  tee -a /etc/ssh/sshd_config <<EOF
$1 $2
EOF
fi

if [ -d /etc/ssh/sshd_config.d ]; then
  find /etc/ssh/sshd_config.d -type f -name "*.conf" | while read -r line; do
    if grep -q "$1" "$line"; then
      echo "[ ## ] change $1 to $2 in $line"
      sed -i "s/$1.*/$1 $2/g" "$line"
    fi
  done
fi
}
sshdmod AllowTcpForwarding no
sshdmod ClientAliveCountMax 2
sshdmod Compression no
sshdmod LogLevel verbose
sshdmod MaxAuthTries 3
sshdmod MaxSessions 2
sshdmod TCPKeepAlive no
sshdmod X11Forwarding no
sshdmod AllowAgentForwarding no

chown root:root /etc/ssh/sshd_config
chmod 0600 /etc/ssh/sshd_config

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
