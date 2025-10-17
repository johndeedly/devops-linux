#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

# Install required packages
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
    libpam-tmpdir needrestart fail2ban cracklib-runtime debsums apt-show-versions clamav rkhunter
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed fail2ban cracklib clamav
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C dnf install -y fail2ban cracklib clamav
fi

# Kernel Hardening
sysctl -w dev.tty.ldisc_autoload=0
sysctl -w fs.protected_fifos=2
sysctl -w fs.protected_hardlinks=1
sysctl -w fs.protected_regular=2
sysctl -w fs.protected_symlinks=1
sysctl -w fs.suid_dumpable=0
sysctl -w 'kernel.core_pattern=|/bin/false'
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
kernel.core_pattern=|/bin/false
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
  sed -i "s/#\? \?$1.*/$1 $2/g" /etc/ssh/sshd_config
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
      sed -i "s/#\? \?$1.*/$1 $2/g" "$line"
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

# no core dumps KRNL-5820
tee -a /etc/security/limits.conf <<EOF
* hard core 0
* soft core 0
EOF

# disable dccp, sctp, rds and tipc NETW-3200
tee -a /etc/modprobe.d/hardening <<EOF
install dccp /bin/true
install sctp /bin/true
install rds  /bin/true
install tipc /bin/true
EOF
tee -a /etc/modprobe.d/blacklist.conf <<EOF
blacklist dccp
blacklist sctp
blacklist rds
blacklist tipc
EOF

# harden compilers to be only executable by root
[ -e "/usr/bin/as" ]  && chmod 0700 "/usr/bin/as"
[ -e "/usr/bin/gcc" ] && chmod 0700 "/usr/bin/gcc"
[ -e "/usr/bin/gpp" ] && chmod 0700 "/usr/bin/gpp"
[ -e "/usr/bin/g++" ] && chmod 0700 "/usr/bin/g++"

# set umask best practice AUTH-9328 (https://github.com/CISOfy/lynis/issues/110)
tee /etc/profile.d/umask.sh <<EOF
# By default, we want umask to get set. This sets it for login shell
# Current threshold for system reserved uid/gids is 200
# You could check uidgid reservation validity in
# /usr/share/doc/setup-*/uidgid file
if [ $UID -gt 199 ] && [ $UID -lt 1000 ]; then
    umask 007
else
    umask 027
fi
EOF

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
