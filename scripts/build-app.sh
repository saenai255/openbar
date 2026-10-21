#!/bin/bash
# Builds OpenBar.app into ./build. Signs with SIGN_IDENTITY, else the identity made by
# create-signing-cert.sh if present, else ad-hoc. A stable identity lets macOS
# keep Accessibility/Screen Recording grants across rebuilds; ad-hoc does not.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/OpenBar.app"
# Local builds take their version from the latest tag so the update check doesn't misfire.
if [ -z "${VERSION:-}" ]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
# UNIVERSAL=1 builds arm64 + x86_64 (needs Xcode, not just Command Line Tools).
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/OpenBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-$VERSION}" "$APP/Contents/Info.plist"
fi

if [ -z "${SIGN_IDENTITY:-}" ]; then
    # "Zubar Code Signing" is the identity's name from before the rename.
    for name in "OpenBar Code Signing" "Zubar Code Signing"; do
        if security find-identity -p codesigning | grep -q "$name"; then SIGN_IDENTITY="$name"; break; fi
    done
fi
codesign --force --timestamp=none --sign "${SIGN_IDENTITY:--}" ${KEYCHAIN:+--keychain "$KEYCHAIN"} "$APP"
echo "Signed with: ${SIGN_IDENTITY:-ad-hoc}"
echo "Built $APP"
