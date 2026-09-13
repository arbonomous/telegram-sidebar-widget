#!/usr/bin/env bash
# Bundle the WKWebView variant as a normal .app (Dock tile + "open" indicator).
# Builds into the gitignored build/ dir, then copies to /Applications — the repo
# root stays clean (no stray .app committed or left behind).
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="SidePiece"
OUT="$SRC_DIR/../build/$NAME.app"
MACOS="$OUT/Contents/MacOS"
RES="$OUT/Contents/Resources"

# Always build fresh icon and logo assets
bash "$SRC_DIR/build-icon.sh"

rm -rf "$OUT"
mkdir -p "$MACOS" "$RES"

"$SRC_DIR/build.sh" "$MACOS/$NAME"

# Copy the official Telegram logo next to the binary (loaded from an explicit
# path at runtime — Bundle resource lookup was unreliable in this project).
if [ -f "$SRC_DIR/../Logo.png" ]; then
  cp "$SRC_DIR/../Logo.png" "$MACOS/Logo.png"
  cp "$SRC_DIR/../Logo.png" "$RES/Logo.png"
fi

# App icon (generated from SidePiece.svg in the repo root).
if [ -f "$SRC_DIR/../build/AppIcon.icns" ]; then
  cp "$SRC_DIR/../build/AppIcon.icns" "$RES/AppIcon.icns"
fi

# LaunchAgent template (for toggleLaunchAtLogin)
if [ -f "$SRC_DIR/com.sidepiece.app.plist" ]; then
  cp "$SRC_DIR/com.sidepiece.app.plist" "$RES/com.sidepiece.app.plist"
fi

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.sidepiece.app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSRequiresAquaSystemAppearance</key><string>false</string>
</dict></plist>
PLIST

# Ad-hoc code sign the bundle to seal the binary, Info.plist, and resources
codesign --force --deep --sign - "$OUT" 2>/dev/null || true

# Install the LaunchAgent so the app auto-starts at login (and relaunches on crash).
LAUNCH_AGENT_SRC="$SRC_DIR/com.sidepiece.app.plist"
LAUNCH_AGENT_DST="$HOME/Library/LaunchAgents/com.sidepiece.app.plist"
if [ -f "$LAUNCH_AGENT_SRC" ]; then
  mkdir -p "$(dirname "$LAUNCH_AGENT_DST")" 2>/dev/null || true
  if cp "$LAUNCH_AGENT_SRC" "$LAUNCH_AGENT_DST" 2>/dev/null; then
    launchctl unload "$LAUNCH_AGENT_DST" 2>/dev/null || true
    launchctl load "$LAUNCH_AGENT_DST" 2>/dev/null || true
  fi
fi

# Copy the built .app to /Applications (the repo-root copy is not kept). Clear
# Gatekeeper/FileProvider flags on BOTH the source and the copy so macOS never
# re-prompts "are you sure you want to open this?" after a rebuild.
xattr -dr com.apple.quarantine "$OUT" 2>/dev/null || true
xattr -dr 'com.apple.fileprovider.fpfs#P' "$OUT" 2>/dev/null || true
if rm -rf "/Applications/$NAME.app" 2>/dev/null && cp -R "$OUT" "/Applications/$NAME.app" 2>/dev/null; then
  xattr -dr com.apple.quarantine "/Applications/$NAME.app" 2>/dev/null || true
  xattr -dr 'com.apple.fileprovider.fpfs#P' "/Applications/$NAME.app" 2>/dev/null || true
  echo "Built $OUT, copied to /Applications, and set to auto-launch at login."
else
  echo "Built $OUT. (Note: could not copy to /Applications due to permissions/sandbox; app bundle is ready in build/)"
fi
