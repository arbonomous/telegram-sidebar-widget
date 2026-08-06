#!/usr/bin/env bash
# Build the WKWebView-based Telegram sidebar (login via QR in the app — no typing).
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$SRC_DIR/../SidePiece}"

swiftc -O \
  -framework AppKit -framework WebKit -framework UserNotifications -framework Cocoa \
  "$SRC_DIR/AppDelegate.swift" \
  "$SRC_DIR/main.swift" \
  -o "$OUT"

echo "Built: $OUT"
