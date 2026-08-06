#!/usr/bin/env bash
# Package the bundled .app into a distributable DMG.
# Usage: bash web/dmg.sh   -> builds TelegramSidebarWeb.app then ./TelegramSidebar.dmg
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SRC_DIR/.." && pwd)"
NAME="TelegramSidebarWeb"
APP="$ROOT/$NAME.app"
STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/TelegramSidebar.dmg"

# 1) Build + bundle the app.
bash "$SRC_DIR/bundle.sh"

# 2) Stage the .app plus an Applications symlink for drag-to-install.
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 3) Create the DMG.
rm -f "$DMG"
hdiutil create -volname "Telegram Sidebar" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo "Built $DMG — send this to your friend. They drag TelegramSidebarWeb.app to Applications."
