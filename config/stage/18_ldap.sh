#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LDAP_ENABLED="$(yq -r '.setup.ldapauth.enabled' /var/lib/cloud/instance/config/setup.yml)"
LDAP_AUTHSERVER="$(yq -r '.setup.ldapauth.authserver' /var/lib/cloud/instance/config/setup.yml)"
LDAP_BASE="$(yq -r '.setup.ldapauth.base' /var/lib/cloud/instance/config/setup.yml)"
LDAP_GROUP="$(yq -r '.setup.ldapauth.group' /var/lib/cloud/instance/config/setup.yml)"
LDAP_PASSWD="$(yq -r '.setup.ldapauth.passwd' /var/lib/cloud/instance/config/setup.yml)"
LDAP_SHADOW="$(yq -r '.setup.ldapauth.shadow' /var/lib/cloud/instance/config/setup.yml)"

if [ -z "$LDAP_ENABLED" ] || [[ "$LDAP_ENABLED" =~ [Nn][Oo] ]] || [[ "$LDAP_ENABLED" =~ [Oo][Ff][Ff] ]] || [[ "$LDAP_ENABLED" =~ [Ff][Aa][Ll][Ss][Ee] ]]
then
  sync
  rm -- "${0}"
  exit 0
fi

# install basic packages
if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install \
    libnss-ldap libpam-ldap ldap-utils nslcd xkcdpass firewalld
elif [ -e /bin/pacman ]; then
  LC_ALL=C yes | LC_ALL=C pacman -S --noconfirm --needed \
    openldap nss-pam-ldapd xkcdpass firewalld
elif [ -e /bin/yum ]; then
  LC_ALL=C yes | LC_ALL=C yum install -y \
    openldap openldap-clients nss-pam-ldapd xkcdpass firewalld
fi

echo ':: enable optional ldap pam and nss authentication'
if [ -f /etc/pam.d/system-auth ]; then
    sed -i '0,/^auth/s//auth       sufficient                  pam_ldap.so\nauth/' /etc/pam.d/system-auth
    sed -i '0,/^account/s//account    sufficient                  pam_ldap.so\naccount/' /etc/pam.d/system-auth
    sed -i '0,/^password/s//password   sufficient                  pam_ldap.so\npassword/' /etc/pam.d/system-auth
    sed -i '0,/^session/s//session    optional                    pam_ldap.so\nsession/' /etc/pam.d/system-auth
fi
if [ -f /etc/pam.d/su ]; then
    sed -i '0,/pam_rootok.so/s//pam_rootok.so\nauth            sufficient      pam_ldap.so/' /etc/pam.d/su
    sed -i 's/^\(auth.*pam_unix.so\)/\1 use_first_pass/' /etc/pam.d/su
    sed -i '0,/^account/s//account         sufficient      pam_ldap.so\naccount/' /etc/pam.d/su
    sed -i '0,/^session/s//session         sufficient      pam_ldap.so\nsession/' /etc/pam.d/su
fi
if [ -f /etc/pam.d/su-l ]; then
    sed -i '0,/pam_rootok.so/s//pam_rootok.so\nauth            sufficient      pam_ldap.so/' /etc/pam.d/su-l
    sed -i 's/^\(auth.*pam_unix.so\)/\1 use_first_pass/' /etc/pam.d/su-l
    sed -i '0,/^account/s//account         sufficient      pam_ldap.so\naccount/' /etc/pam.d/su-l
    sed -i '0,/^session/s//session         sufficient      pam_ldap.so\nsession/' /etc/pam.d/su-l
fi
if [ -f /etc/nslcd.conf ]; then
  chmod 0600 /etc/nslcd.conf
  sed -i "s|^\(uri .*\)|#\1\nuri ${LDAP_AUTHSERVER}|" /etc/nslcd.conf
  sed -i "s|^\(base .*\)|#\1\nbase   ${LDAP_BASE}\nbase   group  ${LDAP_GROUP}\nbase   passwd ${LDAP_PASSWD}\nbase   shadow ${LDAP_SHADOW}|" /etc/nslcd.conf
fi
if [ -f /etc/nsswitch.conf ]; then
    sed -i 's/^\(passwd.*\)/\1 ldap/' /etc/nsswitch.conf
    sed -i 's/^\(group.*\)/\1 ldap/' /etc/nsswitch.conf
    sed -i 's/^\(shadow.*\)/\1 ldap/' /etc/nsswitch.conf
fi
if [ -f /etc/openldap/ldap.conf ]; then
  tee -a /etc/openldap/ldap.conf <<EOF

BASE    ${LDAP_BASE}
URI     ${LDAP_AUTHSERVER}
EOF
fi
if [ -f /etc/pam.d/sudo ]; then
    sed -i 's/^\(auth.*pam_unix.so\)/auth      sufficient    pam_ldap.so\n\1 try_first_pass/' /etc/pam.d/sudo
fi

# Enable all configured services
systemctl enable nslcd.service

# sync everything to disk
sync

# cleanup
rm -- "${0}"
