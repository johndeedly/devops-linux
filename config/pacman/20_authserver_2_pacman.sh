#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

BASEDC="internal"
BASEDN="dc=${BASEDC}"
PASSWD=$(grep -oP '^olcRootPW: \K\w+' /etc/openldap/config.ldif)

# populate LDAP tree with base data
tee -a /tmp/base.ldif <<EOF
# ${BASEDN}
dn: ${BASEDN}
dc: ${BASEDC}
o: Organization
objectClass: dcObject
objectClass: organization

# Manager, ${BASEDC}
dn: cn=Manager,${BASEDN}
cn: Manager
description: LDAP administrator
objectClass: top
objectClass: organizationalRole
roleOccupant: ${BASEDN}

# People, ${BASEDC}
dn: ou=People,${BASEDN}
ou: People
objectClass: top
objectClass: organizationalUnit

# Groups, ${BASEDC}
dn: ou=Groups,${BASEDN}
ou: Groups
objectClass: top
objectClass: organizationalUnit
EOF
echo -en "${PASSWD}\n" | (ldapadd -D "cn=Manager,${BASEDN}" -W -f /tmp/base.ldif)
rm /tmp/base.ldif

# counters
_uid=$((10000))

# adding groups
tee -a /tmp/groups.ldif <<EOF
dn: cn=usr,ou=Groups,${BASEDN}
objectClass: top
objectClass: posixGroup
cn: usr
gidNumber: 9999

dn: cn=adm,ou=Groups,${BASEDN}
objectClass: top
objectClass: posixGroup
cn: adm
gidNumber: 9998
EOF
echo -en "${PASSWD}\n" | (ldapadd -D "cn=Manager,${BASEDN}" -W -f /tmp/groups.ldif)
rm /tmp/groups.ldif

# adding users
getent passwd | while IFS=: read -r username x uid gid gecos home shell; do
  if [ -n "$home" ] && [ -d "$home" ] && [ "$home" != "/" ]; then
    if [ "$uid" -eq 0 ] || [ "$uid" -ge 1000 ]; then
      echo ":: add $username to LDAP users [$uid:$gid]"
      USERHASH=$(grep -oP "^$username:\\K[^:]+" /etc/shadow)
      tee "/tmp/usr_$username.ldif" <<EOF
dn: uid=$username,ou=People,${BASEDN}
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

dn: cn=$username,ou=Groups,${BASEDN}
objectClass: top
objectClass: posixGroup
cn: $username
gidNumber: ${_uid}
memberUid: $username

EOF
      if [ "$uid" -eq 0 ]; then
        tee -a "/tmp/usr_$username.ldif" <<EOF
dn: cn=adm,ou=Groups,${BASEDN}
changetype: modify
add: memberUid
memberUid: $username
EOF
      elif [ "$uid" -ge 1000 ]; then
        tee -a "/tmp/usr_$username.ldif" <<EOF
dn: cn=usr,ou=Groups,${BASEDN}
changetype: modify
add: memberUid
memberUid: $username
EOF
      fi
      echo -en "${PASSWD}\n" | (ldapadd -D "cn=Manager,${BASEDN}" -W -f "/tmp/usr_$username.ldif")
      rm "/tmp/usr_$username.ldif"
      _uid=$((_uid + 1))
    fi
  fi
done

# sync everything to disk
find /etc/openldap/slapd.d/ -d -print
sync

# cleanup
chown -R ldap:ldap /etc/openldap/*
rm -- "${0}"
