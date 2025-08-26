#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

BASEDC="internal"
BASEDN="dc=${BASEDC}"
PASSWD=$(grep -oP '^olcRootPW: \K\w+' /etc/ldap/config.ldif)

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
_firstadmin=$((1))
_firstuser=$((1))

# adding users and groups
getent passwd | while IFS=: read -r username x uid gid gecos home shell; do
  if [ -n "$home" ] && [ -d "$home" ] && [ "$home" != "/" ]; then
    if [ "$uid" -eq 0 ] || [ "$uid" -ge 1000 ]; then
      echo ":: add $username to LDAP users [$uid:$gid]"
      USERHASH=$(grep -oP "^$username:\\K[^:]+" /etc/shadow)
      tee "/tmp/usr_$username.ldif" <<EOF
# New User, ${BASEDC}
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

# New User Group, ${BASEDC}
dn: cn=$username,ou=Groups,${BASEDN}
objectClass: top
objectClass: posixGroup
objectClass: groupOfNames
cn: $username
gidNumber: ${_uid}
memberUid: $username
member: uid=$username,ou=People,${BASEDN}

EOF
      if [ "$uid" -eq 0 ]; then
        if [ "$_firstadmin" -eq 1 ]; then
          tee -a "/tmp/usr_$username.ldif" <<EOF
# New Admin Group, ${BASEDC}
dn: cn=admins,ou=Groups,${BASEDN}
objectClass: top
objectClass: posixGroup
objectClass: groupOfNames
cn: admins
gidNumber: 9998
memberUid: $username
member: uid=$username,ou=People,${BASEDN}

EOF
          _firstadmin=$((0))
        else
          tee -a "/tmp/usr_$username.ldif" <<EOF
# Add to Admin Group, ${BASEDC}
dn: cn=admins,ou=Groups,${BASEDN}
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: uid=$username,ou=People,${BASEDN}

EOF
        fi
      fi
      if [ "$_firstuser" -eq 1 ]; then
        tee -a "/tmp/usr_$username.ldif" <<EOF
# New User Group, ${BASEDC}
dn: cn=users,ou=Groups,${BASEDN}
objectClass: top
objectClass: posixGroup
objectClass: groupOfNames
cn: users
gidNumber: 9999
memberUid: $username
member: uid=$username,ou=People,${BASEDN}

EOF
        _firstuser=$((0))
      else
        tee -a "/tmp/usr_$username.ldif" <<EOF
# Add to User Group, ${BASEDC}
dn: cn=users,ou=Groups,${BASEDN}
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: uid=$username,ou=People,${BASEDN}

EOF
      fi
      echo -en "${PASSWD}\n" | (ldapadd -D "cn=Manager,${BASEDN}" -W -f "/tmp/usr_$username.ldif")
      rm "/tmp/usr_$username.ldif"
      _uid=$((_uid + 1))
    fi
  fi
done

# sync everything to disk
find /etc/ldap/slapd.d/ -d -print
sync

# cleanup
chown -R openldap:openldap /etc/ldap/*
[ -f "${0}" ] && rm -- "${0}"
