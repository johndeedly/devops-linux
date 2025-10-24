#cloud-boothook
#!/usr/bin/sh

# improve boot time by not waiting for ntp
if [ -f /usr/lib/systemd/system/systemd-time-wait-sync.service ]; then
  systemctl stop systemd-time-wait-sync.service
  systemctl disable systemd-time-wait-sync.service
  systemctl mask time-sync.target
fi

# enable ssh provision login -> disable root, allow provisioning account, password auth, use pam
sed -i 's/^#\? \?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\? \?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\? \?AllowTcpForwarding.*/AllowTcpForwarding no/' /etc/ssh/sshd_config
sed -i 's/^#\? \?AllowAgentForwarding.*/AllowAgentForwarding no/' /etc/ssh/sshd_config
sed -i 's/^#\? \?X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/^#\? \?TCPKeepAlive.*/TCPKeepAlive no/' /etc/ssh/sshd_config
sed -i 's/^#\? \?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
# remove all occurences of Match User root until the next empty line
sed -i '/^Match User root/,/^$/d' /etc/ssh/sshd_config
# remove empty lines at end of file
sed -i ':a;/^[ \n]*$/{$d;N;ba}' /etc/ssh/sshd_config
tee -a /etc/ssh/sshd_config <<EOF

Match User root
PasswordAuthentication no
EOF

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
