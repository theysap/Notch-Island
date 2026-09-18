#!/bin/bash
#
# Builds NotchIsland.app into dist/.
#
# The bundle is assembled by hand rather than by Xcode: the project is a Swift
# package, and everything the app needs at runtime — the bridge library, the
# host script, the icon — is copied into place here.
#
# Signing:
#   Set DEVELOPER_ID_APPLICATION to a Developer ID identity to sign properly.
#   Without it the bundle is signed ad-hoc, which runs fine but makes Gatekeeper
#   ask the first time. See README.md.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="NotchIsland"
BUNDLE_ID="com.notchisland.app"
VERSION="$(cat VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
CONFIGURATION="${CONFIGURATION:-release}"

DIST="dist"
APP="${DIST}/${APP_NAME}.app"
CONTENTS="${APP}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
FRAMEWORKS="${CONTENTS}/Frameworks"

GREEN=$'\033[0;32m'
RESET=$'\033[0m'
step() { echo "${GREEN}==>${RESET} $*"; }

step "Building ${APP_NAME} ${VERSION} (build ${BUILD_NUMBER}, ${CONFIGURATION})"
swift build -c "${CONFIGURATION}" 2>&1 | grep -vE "ld: warning: search path" || true

BUILD_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"

if [ ! -x "${BUILD_DIR}/${APP_NAME}" ]; then
    echo "Build did not produce ${BUILD_DIR}/${APP_NAME}" >&2
    exit 1
fi

step "Assembling bundle"
rm -rf "${APP}"
mkdir -p "${MACOS_DIR}" "${RESOURCES}" "${FRAMEWORKS}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# Loaded by the host process, never linked against the app, so it lives beside
# the other private code rather than being linked in.
cp "${BUILD_DIR}/libNotchMediaBridge.dylib" "${FRAMEWORKS}/libNotchMediaBridge.dylib"
cp "Resources/notch-media-bridge.pl" "${RESOURCES}/notch-media-bridge.pl"
chmod +x "${RESOURCES}/notch-media-bridge.pl"

step "Rendering icon"
ICONSET="$(mktemp -d)/${APP_NAME}.iconset"
swift Scripts/make-icon.swift "${ICONSET}" > /dev/null
iconutil -c icns "${ICONSET}" -o "${RESOURCES}/AppIcon.icns"
rm -rf "${ICONSET}"

# The terms travel with the application. They used to sit loose in the disk
# image, which cluttered a window that is now down to two icons and an arrow.
cp LICENSE "${RESOURCES}/LICENSE.txt"

step "Writing Info.plist"
cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <!-- No Dock icon and no menu: the island is the interface. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT licensed. See LICENSE.</string>
    <!-- Shown in the Automation prompt. Without this key macOS denies the
         Apple event instead of asking, and library artwork never loads. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>${APP_NAME} asks Music for the artwork of tracks in your library, and for where playback has actually got to. Both are things macOS will not report any other way.</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

plutil -lint "${CONTENTS}/Info.plist" > /dev/null

printf 'APPL????' > "${CONTENTS}/PkgInfo"

step "Signing"
if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
    IDENTITY="${DEVELOPER_ID_APPLICATION}"
    # Notarisation refuses anything without a secure timestamp, so a real
    # identity gets one. An ad-hoc signature cannot have one at all.
    TIMESTAMP="--timestamp"
    echo "    identity: ${IDENTITY}"
else
    IDENTITY="-"
    TIMESTAMP="--timestamp=none"
    echo "    ad-hoc (set DEVELOPER_ID_APPLICATION to sign for distribution)"
fi

# Nested code has to be signed before the bundle that contains it, or the outer
# signature seals a hash that is about to change.
# The hardened runtime blocks Apple events unless the app carries the
# automation entitlement, and a bundle signature does not cover the inner
# executable's entitlements — so both are signed with it.
ENTITLEMENTS="Resources/${APP_NAME}.entitlements"

# The bridge library is loaded by the Perl host and sends no Apple events, so
# it stays entitlement-free.
codesign --force ${TIMESTAMP} --options runtime --sign "${IDENTITY}" \
    "${FRAMEWORKS}/libNotchMediaBridge.dylib"
codesign --force ${TIMESTAMP} --options runtime --entitlements "${ENTITLEMENTS}" \
    --sign "${IDENTITY}" "${MACOS_DIR}/${APP_NAME}"
codesign --force ${TIMESTAMP} --options runtime --entitlements "${ENTITLEMENTS}" \
    --sign "${IDENTITY}" "${APP}"

codesign --verify --deep --strict "${APP}"

# A missing automation entitlement is invisible until someone plays a library
# track and gets the Music icon instead of a cover, so it is checked here.
# grep, not `plutil -extract`: that reads dots in the key as a key path and
# goes looking for a nested "com" -> "apple" -> ... dictionary that is not there.
if ! codesign -d --entitlements - --xml "${APP}" 2>/dev/null \
    | grep -q "com.apple.security.automation.apple-events"; then
    echo "Signed bundle is missing com.apple.security.automation.apple-events" >&2
    exit 1
fi

step "Built ${APP}"
du -sh "${APP}" | awk '{print "    size: " $1}'
