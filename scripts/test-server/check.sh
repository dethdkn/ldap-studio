#!/usr/bin/env bash
set -euo pipefail

# Builds and runs checks/ against the test server started by run.sh:
# opening the tree, lazy and paged child loads, per-node errors, Go to DN,
# refresh, quick and advanced search, cancellation, connection reuse,
# LDAPS/StartTLS pinning, copy/move/export/delete of a branch, a network
# that stops answering, a server restart, and the SSH tunnel (through a
# throwaway sshd on port 2222). Restarts the test server once.
#
#   scripts/test-server/run.sh start
#   scripts/test-server/check.sh

cd "$(dirname "$0")/../.."
if [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

make -C core >/dev/null
OUT="$(mktemp -d)"

B="$(brew --prefix)/opt"
xcrun -sdk macosx swiftc -O -swift-version 5 -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature InferSendableFromCaptures \
    -import-objc-header ldap-studio/ldap-studio-Bridging-Header.h -Icore/include \
    ldap-studio/Core/LdapStudioCore.swift ldap-studio/Core/LdapConnectionPool.swift \
    ldap-studio/Core/DN.swift ldap-studio/Core/OperationLog.swift \
    ldap-studio/Core/SSHHostKeyFingerprint.swift ldap-studio/SavedConnection.swift \
    ldap-studio/Browser/DirectoryEntry.swift ldap-studio/Browser/DirectoryTree.swift \
    ldap-studio/Browser/EntryActions.swift ldap-studio/Browser/LDIFParser.swift \
    scripts/test-server/checks/*.swift \
    core/build/libldapstudio.a \
    -L"$B/openldap/lib" -L"$B/openssl@3/lib" -L"$B/libxcrypt/lib" -L"$B/libssh2/lib" \
    -lldap -llber -lcrypto -lcrypt -lssh2 -framework ImageIO -framework CoreGraphics \
    -o "$OUT/checks"

# A proxy to freeze, imitating a network that stops answering.
python3 scripts/test-server/checks/proxy.py 4389 3389 &
PROXY_PID=$!
SSHD_PID=""
cleanup() {
    kill -CONT "$PROXY_PID" 2>/dev/null || true
    kill "$PROXY_PID" 2>/dev/null || true
    if [[ -n "$SSHD_PID" ]]; then
        kill "$SSHD_PID" 2>/dev/null || true
        wait "$SSHD_PID" 2>/dev/null || true
    fi
    rm -rf "$OUT"
}
trap cleanup EXIT
sleep 0.5

DIR="${LDS_TEST_DIR:-/tmp/ldap-studio-test-server}"
PIN="$(openssl x509 -in "$DIR/server.crt" -outform der | shasum -a 256 | cut -d' ' -f1)" \
PROXY_PORT=4389 PROXY_PID="$PROXY_PID" RUN_SCRIPT="$PWD/scripts/test-server/run.sh" \
    "$OUT/checks"

# The SSH tunnel, through a throwaway sshd on port 2222 that only
# accepts a key generated here.
if [[ -x /usr/sbin/sshd ]]; then
    ssh-keygen -q -t ed25519 -N "" -f "$OUT/hostkey"
    ssh-keygen -q -t ed25519 -N "" -f "$OUT/clientkey"
    cp "$OUT/clientkey.pub" "$OUT/authorized_keys"
    cat > "$OUT/sshd_config" <<CONF
Port 2222
ListenAddress 127.0.0.1
HostKey $OUT/hostkey
PidFile $OUT/sshd.pid
AuthorizedKeysFile $OUT/authorized_keys
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowTcpForwarding yes
ClientAliveInterval 1
CONF
    /usr/sbin/sshd -D -f "$OUT/sshd_config" -E "$OUT/sshd.log" &
    SSHD_PID=$!
    for _ in $(seq 50); do nc -z 127.0.0.1 2222 2>/dev/null && break; sleep 0.1; done
    clang -std=c11 -Icore/include -I"$B/openldap/include" scripts/test-server/checks/ssh_check.c core/build/libldapstudio.a \
        -L"$B/openldap/lib" -L"$B/openssl@3/lib" -L"$B/libxcrypt/lib" -L"$B/libssh2/lib" \
        -lldap -llber -lcrypto -lcrypt -lssh2 -framework ImageIO -framework CoreGraphics \
        -o "$OUT/ssh_check"
    "$OUT/ssh_check" "$OUT/clientkey"
fi
