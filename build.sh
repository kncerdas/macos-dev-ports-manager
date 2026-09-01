#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/DevPorts.app"
CONFIG="${CONFIG:-release}"

echo "==> Generating app icon"
"$ROOT/Scripts/make-icon.sh" || echo "    (icon generation skipped)"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

echo "==> Assembling DevPorts.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DevPorts" "$APP/Contents/MacOS/DevPorts"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc signing"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Done: $APP"
