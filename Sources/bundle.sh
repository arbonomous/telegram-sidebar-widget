#!/usr/bin/env bash
# Bundle the WKWebView variant as a .app (LSUIElement accessory, no Dock icon).
# Builds into the gitignored build/ dir, then copies to /Applications — the repo
# root stays clean (no stray .app committed or left behind).
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="SidePiece"
OUT="$SRC_DIR/../build/$NAME.app"
MACOS="$OUT/Contents/MacOS"
RES="$OUT/Contents/Resources"

# Ensure the app icon exists (regenerate from SidePiece.svg if missing).
if [ ! -f "$SRC_DIR/../build/AppIcon.icns" ]; then
  bash "$SRC_DIR/build-icon.sh"
fi

rm -rf "$OUT"
mkdir -p "$MACOS" "$RES"

"$SRC_DIR/build.sh" "$MACOS/$NAME"

# Copy the official Telegram logo next to the binary (loaded from an explicit
# path at runtime — Bundle resource lookup was unreliable in this project).
if [ -f "$SRC_DIR/../Logo.png" ]; then
  cp "$SRC_DIR/../Logo.png" "$MACOS/Logo.png"
fi

# App icon (generated from SidePiece.svg in the repo root).
if [ -f "$SRC_DIR/../build/AppIcon.icns" ]; then
  cp "$SRC_DIR/../build/AppIcon.icns" "$RES/AppIcon.icns"
fi

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.sidepiece.app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><string>true</string>
  <key>NSRequiresAquaSystemAppearance</key><string>false</string>
</dict></plist>
PLIST

# Install the LaunchAgent so the app auto-starts at login (and relaunches on crash).
LAUNCH_AGENT_SRC="$SRC_DIR/com.sidepiece.app.plist"
LAUNCH_AGENT_DST="$HOME/Library/LaunchAgents/com.sidepiece.app.plist"
if [ -f "$LAUNCH_AGENT_SRC" ]; then
  cp "$LAUNCH_AGENT_SRC" "$LAUNCH_AGENT_DST"
  launchctl load "$LAUNCH_AGENT_DST" 2>/dev/null || true
fi

# Copy the built .app to /Applications (the repo-root copy is not kept).
rm -rf "/Applications/$NAME.app"
cp -R "$OUT" "/Applications/$NAME.app"

echo "Built $OUT, copied to /Applications, and set to auto-launch at login."
