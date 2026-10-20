#!/usr/bin/env bash
set -euo pipefail

# A local OpenLDAP server for testing ldap-studio against a large
# directory, built from Homebrew's openldap (see ../../Brewfile) — no
# Docker needed.
#
#   scripts/test-server/run.sh start   generate data (first run), start slapd
#   scripts/test-server/run.sh stop
#   scripts/test-server/run.sh reset   stop, delete all data, start fresh
#
# Listens on ldap://127.0.0.1:3389 (StartTLS available) and
# ldaps://127.0.0.1:3636 (self-signed certificate). Two suffixes:
#
#   dc=example,dc=com  ~151k entries; ou=People has 76,000 direct children
#   dc=small,dc=test   a couple of dozen entries
#
# Like Active Directory's MaxPageSize, a plain search returns at most 500
# entries ("Size limit exceeded"); a paged search (RFC 2696) can read
# everything, 500 per page. The rootdn ignores limits, so bind as one of:
#
#   cn=manager,ou=Service,dc=example,dc=com / manager   read + write
#   cn=reader,ou=Service,dc=example,dc=com  / reader    read only
#   cn=manager,dc=small,dc=test             / manager   small directory
#
# ou=Restricted is listed in the tree but can't be searched under, so
# expanding it fails — for checking per-node errors.

cd "$(dirname "$0")"

DIR="${LDS_TEST_DIR:-/tmp/ldap-studio-test-server}"
OPENLDAP="$(brew --prefix openldap)"
SLAPD="$OPENLDAP/libexec/slapd"
SCHEMA="$(brew --prefix)/etc/openldap/schema"
PIDFILE="$DIR/slapd.pid"

stop() {
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        echo "stopped slapd"
    fi
}

write_config() {
    cat > "$DIR/slapd.conf" <<EOF
include         $SCHEMA/core.schema
include         $SCHEMA/cosine.schema
include         $SCHEMA/inetorgperson.schema
include         $SCHEMA/nis.schema

pidfile         $PIDFILE
argsfile        $DIR/slapd.args

TLSCertificateFile    $DIR/server.crt
TLSCertificateKeyFile $DIR/server.key

database        mdb
maxsize         4294967296
suffix          "dc=example,dc=com"
rootdn          "cn=admin,dc=example,dc=com"
rootpw          secret
directory       $DIR/example
index           objectClass eq
index           cn,uid,ou,mail,sn,givenName eq,sub
# AD-like: plain searches stop at 500, paged searches see everything.
limits          users size.soft=500 size.hard=500 size.pr=500 size.prtotal=unlimited
limits          anonymous size.soft=500 size.hard=500 size.pr=500 size.prtotal=unlimited

# The ou=Restricted entry itself can be read (so it shows up in its
# parent's listing) but not searched, so a search based at it is refused.
access to dn.base="ou=Restricted,dc=example,dc=com" attrs=entry
        by users =rd
access to dn.children="ou=Restricted,dc=example,dc=com"
        by * none
access to attrs=userPassword
        by dn.exact="cn=manager,ou=Service,dc=example,dc=com" write
        by self write
        by anonymous auth
        by * none
access to *
        by dn.exact="cn=manager,ou=Service,dc=example,dc=com" write
        by users read
        by anonymous auth

database        mdb
maxsize         104857600
suffix          "dc=small,dc=test"
rootdn          "cn=admin,dc=small,dc=test"
rootpw          secret
directory       $DIR/small
index           objectClass eq
access to attrs=userPassword
        by dn.exact="cn=manager,dc=small,dc=test" write
        by anonymous auth
        by * none
access to *
        by dn.exact="cn=manager,dc=small,dc=test" write
        by users read
        by anonymous auth
EOF
}

seed() {
    mkdir -p "$DIR/example" "$DIR/small"
    if [[ ! -f "$DIR/server.crt" ]]; then
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -subj "/CN=127.0.0.1" -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" \
            -keyout "$DIR/server.key" -out "$DIR/server.crt" 2>/dev/null
    fi
    write_config
    if [[ ! -f "$DIR/example/data.mdb" ]]; then
        echo "==> generating test data"
        python3 generate.py "$DIR"
        echo "==> loading dc=example,dc=com (takes a minute)"
        "$OPENLDAP/sbin/slapadd" -q -f "$DIR/slapd.conf" -b "dc=example,dc=com" -l "$DIR/example.ldif"
        "$OPENLDAP/sbin/slapadd" -q -f "$DIR/slapd.conf" -b "dc=small,dc=test" -l "$DIR/small.ldif"
    fi
}

start() {
    seed
    stop
    "$SLAPD" -f "$DIR/slapd.conf" -h "ldap://127.0.0.1:3389/ ldaps://127.0.0.1:3636/"
    echo "slapd running: ldap://127.0.0.1:3389  ldaps://127.0.0.1:3636  (data in $DIR)"
}

case "${1:-start}" in
    start) start ;;
    stop) stop ;;
    reset) stop; rm -rf "$DIR"; start ;;
    *) echo "usage: $0 start|stop|reset" >&2; exit 1 ;;
esac
