#!/usr/bin/env bash
set -euo pipefail

# Builds and runs checks/ against the test server started by run.sh:
# opening the tree, lazy and paged child loads, per-node errors, Go to DN,
# refresh, quick and advanced search, cancellation, connection reuse,
# LDAPS/StartTLS pinning, and copy/move/export/delete of a branch.
#
#   scripts/test-server/run.sh start
#   scripts/test-server/check.sh

cd "$(dirname "$0")/../.."
if [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

make -C core >/dev/null
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

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

DIR="${LDS_TEST_DIR:-/tmp/ldap-studio-test-server}"
PIN="$(openssl x509 -in "$DIR/server.crt" -outform der | shasum -a 256 | cut -d' ' -f1)" \
    "$OUT/checks"
