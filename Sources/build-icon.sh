#!/usr/bin/env bash
# Regenerate the app icon (build/AppIcon.icns) from SidePiece.svg.
# Safe to re-run; the .icns is gitignored (regenerable from tracked SVG source).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/SidePiece.svg"
OUT_DIR="$ROOT/build"
ICONSET="$OUT_DIR/icon.iconset"
ICNS="$OUT_DIR/AppIcon.icns"

command -v rsvg-convert >/dev/null 2>&1 || { echo "Need rsvg-convert (brew install librsvg)"; exit 1; }

mkdir -p "$ICONSET"
# sizes: base @1x and @2x (retina) per Apple HIG
declare -a sizes=(16 32 64 128 256 512)
for s in "${sizes[@]}"; do
  d=$((s*2))
  rsvg-convert -w "$s"  -h "$s"  "$SRC" -o "$ICONSET/icon_${s}x${s}.png"
  rsvg-convert -w "$d"  -h "$d"  "$SRC" -o "$ICONSET/icon_${s}x${s}@2x.png"
done

rm -f "$ICNS"
iconutil --convert icns --output "$ICNS" "$ICONSET"
echo "Built $ICNS"
