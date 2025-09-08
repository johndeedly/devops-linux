#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ -z "${line[@]}" ] && line=( '' ); TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive eatmydata apt -y install slapd ldap-utils xkcdpass

tee /etc/ldap/schema/rfc2307bis.ldif >/dev/null <<EOF
$(</var/lib/cloud/instance/provision/apt/20_authserver_apt/rfc2307bis.ldif)
EOF

install -m 0700 -o openldap -g openldap -d /var/lib/ldap/openldap-data
install -m 0760 -o root -g openldap -d /etc/ldap/slapd.d

LDAP_BASE_DC="$(yq -r '.setup.authserver.base_dc' /var/lib/cloud/instance/config/setup.yml)"
LDAP_BASE_DN="$(yq -r '.setup.authserver.base_dn' /var/lib/cloud/instance/config/setup.yml)"
LDAP_MGMT_CN="$(yq -r '.setup.authserver.mgmt_cn' /var/lib/cloud/instance/config/setup.yml)"
LDAP_MGMT_DN="$(yq -r '.setup.authserver.mgmt_dn' /var/lib/cloud/instance/config/setup.yml)"

PASSWD=$(xkcdpass -w ger-anlx -R -D '1234567890' -v '[A-Xa-x]' --min=4 --max=8 -n 3)

tee /etc/ldap/config.ldif <<EOF
# The root config entry
dn: cn=config
objectClass: olcGlobal
cn: config
olcArgsFile: /var/run/slapd/slapd.args
olcPidFile: /var/run/slapd/slapd.pid

# The config database
dn: olcDatabase=config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: config
olcRootDN: ${LDAP_MGMT_DN}

# Module back_mdb
dn: cn=module,cn=config
cn: module
objectClass: olcModuleList
objectClass: top
olcModuleLoad: back_mdb.so
olcModulePath: /usr/lib/ldap

# Schemas
dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

# TODO: Include further schemas as necessary
include: file:///etc/ldap/schema/core.ldif
# RFC1274: Cosine and Internet X.500 schema
include: file:///etc/ldap/schema/cosine.ldif
# RFC2307: An Approach for Using LDAP as a Network Information Service
include: file:///etc/ldap/schema/rfc2307bis.ldif
# RFC2798: Internet Organizational Person
include: file:///etc/ldap/schema/inetorgperson.ldif

# The database for our entries
dn: olcDatabase=mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: mdb
olcSuffix: ${LDAP_BASE_DN}
olcRootDN: ${LDAP_MGMT_DN}
olcRootPW: $PASSWD
olcDbDirectory: /var/lib/ldap/openldap-data
# TODO: Access Control List (https://www.openldap.org/doc/admin24/access-control.html)
#   The first ACL allows users to update (but not read) their passwords, anonymous users
#   to authenticate against this attribute, and (implicitly) denying all access to others.
olcAccess: to attrs=userPassword by self =xw by anonymous auth by * none
#   The second ACL grants authentication against the rootdn only from the local machine.
olcAccess: to dn.base="${LDAP_MGMT_DN}" by peername.regex=127\.0\.0\.1 auth by users none by * none
#   The third ACL allows (implicitly) everyone and anyone read access to all other entries.
olcAccess: to * by * read
# TODO: Create further indexes
olcDbIndex: objectClass eq
olcDbIndex: uid pres,eq
olcDbIndex: mail pres,sub,eq
olcDbIndex: cn,sn pres,sub,eq
olcDbIndex: dc eq

# Module memberOf
dn: cn=module,cn=config
cn: module
objectClass: olcModuleList
objectClass: top
olcModuleLoad: memberof.so
olcModulePath: /usr/lib/ldap

dn: olcOverlay=memberof,olcDatabase={1}mdb,cn=config
olcOverlay: memberof
objectClass: olcConfig
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: top
olcMemberOfRefint: TRUE

# Module refint
dn: cn=module,cn=config
cn: module
objectClass: olcModuleList
objectClass: top
olcModuleLoad: refint.so
olcModulePath: /usr/lib/ldap

dn: olcOverlay=refint,olcDatabase={1}mdb,cn=config
olcOverlay: refint
objectClass: olcConfig
objectClass: olcOverlayConfig
objectClass: olcRefintConfig
objectClass: top
olcRefintAttribute: memberof
olcRefintAttribute: member
olcRefintAttribute: manager
olcRefintAttribute: owner
EOF
if [ "$(ls -A /etc/ldap/slapd.d)" ]; then
  rm -r /etc/ldap/slapd.d/*
fi
slapadd -n 0 -F /etc/ldap/slapd.d/ -l /etc/ldap/config.ldif

# Enable all configured services
systemctl enable slapd.service

# sync everything to disk
find /etc/ldap/slapd.d/ -d -print | sort
sync

# cleanup
chown -R openldap:openldap /etc/ldap/*
[ -f "${0}" ] && rm -- "${0}"
