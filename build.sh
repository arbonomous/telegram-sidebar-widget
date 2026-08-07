#!/usr/bin/env bash
# SidePiece — one-command build.
#
#   bash build.sh           # build + bundle the .app, install to /Applications,
#                           # set it to auto-launch at login, and rebuild the DMG
#   bash build.sh --icon    # also regenerate the app icon from SidePiece.svg
#   bash build.sh --dmg     # only rebuild dist/SidePiece.dmg (uses existing .app)
#
# The compiled .app, the .icns, and the .dmg are all regenerable artifacts and
# are git-ignored. Only the SOURCE (swift, svg, scripts) lives in git.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/Sources"

case "${1:-}" in
  --icon)
    bash "$SRC/build-icon.sh"
    bash "$SRC/bundle.sh"
    bash "$SRC/dmg.sh"
    ;;
  --dmg)
    bash "$SRC/dmg.sh"
    ;;
  "")
    bash "$SRC/bundle.sh"
    bash "$SRC/dmg.sh"
    echo "Done. SidePiece.app installed to /Applications and dist/SidePiece.dmg rebuilt."
    ;;
  *)
    echo "Usage: bash build.sh [--icon|--dmg]" >&2
    exit 1
    ;;
esac
