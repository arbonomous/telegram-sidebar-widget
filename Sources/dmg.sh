#!/usr/bin/env bash
# Package the bundled .app into distributable formats (.zip and .dmg)
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SRC_DIR/.." && pwd)"
NAME="SidePiece"
APP="$ROOT/build/$NAME.app"
STAGE="$ROOT/build/dmg-stage"
DIST="$ROOT/dist"
ZIP="$DIST/$NAME.zip"
DMG="$DIST/$NAME.dmg"

# 1) Build + bundle the app
bash "$SRC_DIR/bundle.sh"

mkdir -p "$DIST"

# 2) Create clean distributable ZIP with Tester's Guide
echo "Creating distributable ZIP archive at $ZIP..."
rm -f "$ZIP"
cp "$ROOT/TESTERS_GUIDE.md" "$DIST/TESTERS_GUIDE.md"
cp "$ROOT/TESTERS_GUIDE.md" "$ROOT/build/TESTERS_GUIDE.md"
(cd "$ROOT/build" && zip -r -q -y "$ZIP" "$NAME.app" "TESTERS_GUIDE.md")
rm -f "$ROOT/build/TESTERS_GUIDE.md"
echo "Built $ZIP — ready for testers."

# 3) Stage the .app plus an Applications symlink and guide for drag-to-install DMG
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp "$ROOT/TESTERS_GUIDE.md" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 4) Create the DMG
rm -f "$DMG"
if hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" 2>/dev/null; then
  echo "Built $DMG — drag-and-drop disk image ready."
else
  echo "Notice: hdiutil requires device privileges in native Terminal. Distributable ZIP is ready at $ZIP."
fi

# Clean up stage directory
rm -rf "$STAGE"
