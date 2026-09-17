#!/bin/bash
#
# Packages dist/NotchIsland.app into a disk image.
#
# Deliberately a plain image — application plus a link to /Applications. Laying
# out a window with a background picture means driving Finder through Apple
# events, which asks the person building for automation permission and fails
# outright on a build machine.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="NotchIsland"
VERSION="$(cat VERSION)"
DIST="dist"
APP="${DIST}/${APP_NAME}.app"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"

GREEN=$'\033[0;32m'
RESET=$'\033[0m'
step() { echo "${GREEN}==>${RESET} $*"; }

if [ ! -d "${APP}" ]; then
    echo "${APP} not found. Run Scripts/build-app.sh first." >&2
    exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

step "Staging ${APP_NAME} ${VERSION}"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

# Gives the person a copy of the terms without having to open the bundle.
cp LICENSE "${STAGING}/LICENSE.txt"

step "Creating disk image"
rm -f "${DMG}"
# ULFO is LZFSE-compressed. `hdiutil create` is deprecated as of macOS 27 in
# favour of this.
diskutil image create from \
    --format ULFO \
    --volumeName "${APP_NAME} ${VERSION}" \
    "${STAGING}" \
    "${DMG}" > /dev/null

if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
    step "Signing disk image"
    codesign --force --sign "${DEVELOPER_ID_APPLICATION}" "${DMG}"
fi

step "Verifying"
diskutil image info "${DMG}" > /dev/null

step "Built ${DMG}"
du -h "${DMG}" | awk '{print "    size: " $1}'
shasum -a 256 "${DMG}" | awk '{print "    sha256: " $1}'
