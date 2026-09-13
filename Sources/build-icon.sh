#!/usr/bin/env bash
# Regenerate AppIcon.icns and Logo.png from vector SVGs using native macOS tools
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

xcrun swift "$ROOT/Sources/build-icon.swift"
echo "Brand assets generated successfully."
