#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PBXPROJ="ldap-studio.xcodeproj/project.pbxproj"
CARGO_TOML="core/Cargo.toml"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree is not clean — commit or stash your changes first." >&2
    exit 1
fi

CURRENT_VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$CARGO_TOML" | head -n1)"
read -rp "New version (current is $CURRENT_VERSION, e.g. 0.1.4): " VERSION

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must look like 0.1.4" >&2
    exit 1
fi

TAG="v$VERSION"

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "error: tag $TAG already exists" >&2
    exit 1
fi

echo "==> Updating Xcode project version to $VERSION"
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $VERSION;/" "$PBXPROJ"

echo "==> Updating Cargo.toml version to $VERSION"
sed -i '' "s/^version = \".*\"/version = \"$VERSION\"/" "$CARGO_TOML"

echo "==> Refreshing Cargo.lock"
(cd core && cargo check --offline --quiet)

git add "$PBXPROJ" "$CARGO_TOML" core/Cargo.lock

echo "==> Committing"
git commit -m "🔖 Release $VERSION"

echo "==> Tagging $TAG"
git tag "$TAG"

echo "==> Pushing to GitHub"
BRANCH="$(git branch --show-current)"
git push origin "$BRANCH"
git push origin "$TAG"

echo "==> Building Release .app"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

xcodebuild \
    -project ldap-studio.xcodeproj \
    -scheme ldap-studio \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build

APP_PATH="$BUILD_DIR/Build/Products/Release/ldap-studio.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: build did not produce $APP_PATH" >&2
    exit 1
fi

echo "==> Packaging dist/ldap-studio-$TAG.zip"
mkdir -p dist
ZIP_PATH="dist/ldap-studio-$TAG.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "Done — release $VERSION:"
echo "  - commit + tag $TAG pushed to origin/$BRANCH"
echo "  - $ZIP_PATH"
