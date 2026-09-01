#!/bin/bash
# Builds a distributable disk image containing DevPorts.app and a drag-to-install
# shortcut to /Applications.
#
# Signing (optional, for distribution to other machines):
#   DEVPORTS_SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./Scripts/make-dmg.sh
#   DEVPORTS_NOTARY_PROFILE=devports ./Scripts/make-dmg.sh   # after `notarytool store-credentials`
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/DevPorts.app"
DIST="$ROOT/dist"
VOLUME="DevPorts"

[ -d "$APP" ] || "$ROOT/build.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/DevPorts-$VERSION.dmg"

# Re-sign with a Developer ID if one was provided; otherwise build.sh's ad-hoc
# signature stands and the image is only useful on this machine.
if [ -n "${DEVPORTS_SIGN_ID:-}" ]; then
  echo "==> Signing app as: $DEVPORTS_SIGN_ID"
  codesign --force --deep --options runtime --timestamp \
           --sign "$DEVPORTS_SIGN_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> No DEVPORTS_SIGN_ID set — keeping the ad-hoc signature (local use only)"
fi

echo "==> Staging"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/DevPorts.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Building $DMG"
mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create \
  -volname "$VOLUME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -quiet \
  "$DMG"

if [ -n "${DEVPORTS_SIGN_ID:-}" ]; then
  echo "==> Signing disk image"
  codesign --force --sign "$DEVPORTS_SIGN_ID" "$DMG"
fi

if [ -n "${DEVPORTS_NOTARY_PROFILE:-}" ]; then
  echo "==> Submitting for notarization (this waits on Apple)"
  xcrun notarytool submit "$DMG" --keychain-profile "$DEVPORTS_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
