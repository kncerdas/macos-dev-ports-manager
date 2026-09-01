#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/.build/AppIcon.iconset"
OUT="$ROOT/Resources/AppIcon.icns"

[ -f "$OUT" ] && [ "$OUT" -nt "$ROOT/Scripts/make-icon.swift" ] && exit 0

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift "$ROOT/Scripts/make-icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "    icon -> $OUT"
