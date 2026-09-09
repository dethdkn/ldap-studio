#!/usr/bin/env bash
set -euo pipefail

# Builds a Release ldap-studio.app and packages it as
# dist/ldap-studio-test.zip (replacing any existing one). No version
# bump, no git, no push — that's what scripts/release.sh is for.

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Release}"
ZIP_PATH="dist/ldap-studio-test.zip"

if [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "==> Building $CONFIGURATION .app"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

xcodebuild \
    -project ldap-studio.xcodeproj \
    -scheme ldap-studio \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR" \
    build

APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/ldap-studio.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: build did not produce $APP_PATH" >&2
    exit 1
fi

echo "==> Packaging $ZIP_PATH"
mkdir -p dist
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "Done — $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"
