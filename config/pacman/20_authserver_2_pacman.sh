#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LDAP_BASE_DC="$(yq -r '.setup.authserver.base_dc' /var/lib/cloud/instance/config/setup.yml)"
LDAP_BASE_DN="$(yq -r '.setup.authserver.base_dn' /var/lib/cloud/instance/config/setup.yml)"
LDAP_GROUP_OU="$(yq -r '.setup.authserver.group_ou' /var/lib/cloud/instance/config/setup.yml)"
LDAP_GROUP_DN="$(yq -r '.setup.authserver.group_dn' /var/lib/cloud/instance/config/setup.yml)"
LDAP_USER_OU="$(yq -r '.setup.authserver.user_ou' /var/lib/cloud/instance/config/setup.yml)"
LDAP_USER_DN="$(yq -r '.setup.authserver.user_dn' /var/lib/cloud/instance/config/setup.yml)"
LDAP_MGMT_CN="$(yq -r '.setup.authserver.mgmt_cn' /var/lib/cloud/instance/config/setup.yml)"
LDAP_MGMT_DN="$(yq -r '.setup.authserver.mgmt_dn' /var/lib/cloud/instance/config/setup.yml)"

PASSWD=$(grep -oP '^olcRootPW: \K\w+' /etc/openldap/config.ldif)

# populate LDAP tree with base data
tee -a /tmp/base.ldif <<EOF
# ${LDAP_BASE_DN}
dn: ${LDAP_BASE_DN}
dc: ${LDAP_BASE_DC}
o: Organization
objectClass: dcObject
objectClass: organization

# ${LDAP_MGMT_CN}, ${LDAP_BASE_DC}
dn: ${LDAP_MGMT_DN}
cn: ${LDAP_MGMT_CN}
description: LDAP administrator
objectClass: top
objectClass: organizationalRole
roleOccupant: ${LDAP_BASE_DN}

# ${LDAP_USER_OU}, ${LDAP_BASE_DC}
dn: ${LDAP_USER_DN}
ou: ${LDAP_USER_OU}
objectClass: top
objectClass: organizationalUnit

# ${LDAP_GROUP_OU}, ${LDAP_BASE_DC}
dn: ${LDAP_GROUP_DN}
ou: ${LDAP_GROUP_OU}
objectClass: top
objectClass: organizationalUnit
EOF
echo -en "${PASSWD}\n" | (ldapadd -D "${LDAP_MGMT_DN}" -W -f /tmp/base.ldif)
rm /tmp/base.ldif

# counters
_uid=$((10000))
_firstadmin=$((1))
_firstuser=$((1))

# adding users and groups
getent passwd | while IFS=: read -r username x uid gid gecos home shell; do
  if [ -n "$home" ] && [ -d "$home" ] && [ "$home" != "/" ]; then
    if [ "$uid" -eq 0 ] || [ "$uid" -ge 1000 ]; then
      echo ":: add $username to LDAP users [$uid:$gid]"
      USERHASH=$(grep -oP "^$username:\\K[^:]+" /etc/shadow)
      tee "/tmp/usr_$username.ldif" <<EOF
# New User, ${LDAP_BASE_DC}
dn: uid=$username,${LDAP_USER_DN}
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: $username
cn: $username
sn: $username
userPassword: {CRYPT}${USERHASH}
loginShell: /bin/bash
uidNumber: ${_uid}
gidNumber: ${_uid}
homeDirectory: /home/$username/

# New User Group, ${LDAP_BASE_DC}
dn: cn=$username,${LDAP_GROUP_DN}
objectClass: top
objectClass: posixGroup
objectClass: groupOfNames
cn: $username
gidNumber: ${_uid}
memberUid: $username
member: uid=$username,${LDAP_USER_DN}

EOF
      if [ "$uid" -eq 0 ]; then
        if [ "$_firstadmin" -eq 1 ]; then
          tee -a "/tmp/usr_$username.ldif" <<EOF
# New Admin Group, ${LDAP_BASE_DC}
dn: cn=admins,${LDAP_GROUP_DN}
objectClass: top
objectClass: posixGroup
objectClass: groupOfNames
cn: admins
gidNumber: 9998
memberUid: $username
member: uid=$username,${LDAP_USER_DN}

EOF
          _firstadmin=$((0))
        else
          tee -a "/tmp/usr_$username.ldif" <<EOF
# Add to Admin Group, ${LDAP_BASE_DC}
dn: cn=admins,${LDAP_GROUP_DN}
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: uid=$username,${LDAP_USER_DN}

EOF
        fi
      fi
      if [ "$_firstuser" -eq 1 ]; then
        tee -a "/tmp/usr_$username.ldif" <<EOF
# New User Group, ${LDAP_BASE_DC}
dn: cn=users,${LDAP_GROUP_DN}
objectClass: top
objectClass: posixGroup
objectClass: groupOfNames
cn: users
gidNumber: 9999
memberUid: $username
member: uid=$username,${LDAP_USER_DN}

EOF
        _firstuser=$((0))
      else
        tee -a "/tmp/usr_$username.ldif" <<EOF
# Add to User Group, ${LDAP_BASE_DC}
dn: cn=users,${LDAP_GROUP_DN}
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: uid=$username,${LDAP_USER_DN}

EOF
      fi
      echo -en "${PASSWD}\n" | (ldapadd -D "${LDAP_MGMT_DN}" -W -f "/tmp/usr_$username.ldif")
      rm "/tmp/usr_$username.ldif"
      _uid=$((_uid + 1))
    fi
  fi
done

# enable authserver mDNS advertising
tee /etc/systemd/dnssd/ldap.dnssd <<EOF
[Service]
Name=%H
Type=_ldap._tcp
Port=389
EOF
tee /etc/systemd/dnssd/ldaps.dnssd <<EOF
[Service]
Name=%H
Type=_ldaps._tcp
Port=636
EOF

# open firewall for rdp access
ufw disable
ufw allow log 389 comment 'allow ldap'
ufw allow log 636 comment 'allow ldaps'
ufw enable
ufw status verbose

# sync everything to disk
find /etc/openldap/slapd.d/ -d -print | sort
sync

# cleanup
chown -R ldap:ldap /etc/openldap/*
[ -f "${0}" ] && rm -- "${0}"
