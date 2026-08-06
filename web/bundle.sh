#!/usr/bin/env bash
# Bundle the WKWebView variant as a .app (LSUIElement accessory, no Dock icon).
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="TelegramSidebarWeb"
OUT="$SRC_DIR/../$NAME.app"
MACOS="$OUT/Contents/MacOS"
RES="$OUT/Contents/Resources"

rm -rf "$OUT"
mkdir -p "$MACOS" "$RES"

"$SRC_DIR/build.sh" "$MACOS/$NAME"

# Copy the official Telegram logo next to the binary (loaded from an explicit
# path at runtime — Bundle resource lookup was unreliable in this project).
if [ -f "$SRC_DIR/../Logo.png" ]; then
  cp "$SRC_DIR/../Logo.png" "$MACOS/Logo.png"
elif [ -f "$SRC_DIR/Logo.png" ]; then
  cp "$SRC_DIR/Logo.png" "$MACOS/Logo.png"
fi

# App icon (generated from Logo.png).
if [ -f "$SRC_DIR/../build/AppIcon.icns" ]; then
  cp "$SRC_DIR/../build/AppIcon.icns" "$RES/AppIcon.icns"
fi

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.user.telegram-sidebar-web</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><string>true</string>
  <key>NSRequiresAquaSystemAppearance</key><string>false</string>
</dict></plist>
PLIST

echo "Built $OUT — drag to /Applications, add to Login Items."
