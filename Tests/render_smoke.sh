#!/bin/bash
# Render smoke-test: launch the bundled app in --selftest mode and confirm the
# WebView actually paints Telegram (not blank/white). Catches regressions like
# the "expanded panel shows white" bug that logic-only tests miss.
#
# Requires: network access (loads web.telegram.org/k) and a window server
# (must run on a logged-in Mac, not a headless CI box).
set -uo pipefail

APP="${1:-/Applications/SidePiece.app}"
BIN="$APP/Contents/MacOS/SidePiece"
test -x "$BIN" || { echo "FAIL: build the app first (bash web/bundle.sh)"; exit 1; }

pgrep -f SidePiece | xargs -r kill 2>/dev/null; sleep 1
rm -f /tmp/tg_selftest.json /tmp/tg_selftest.png

# Launch the real app binary in self-test mode (it quits itself after reporting).
"$BIN" --selftest >/dev/null 2>&1 &

# Wait up to 60s for the report.
for i in $(seq 1 60); do
  [ -f /tmp/tg_selftest.json ] && break
  sleep 1
done

if [ ! -f /tmp/tg_selftest.json ]; then
  echo "FAIL: self-test produced no result (app failed to launch or render)"
  exit 1
fi

echo "self-test report: $(cat /tmp/tg_selftest.json)"
ok=$(python3 -c "import json; print(json.load(open('/tmp/tg_selftest.json')).get('ok'))" 2>/dev/null)
if [ "$ok" = "True" ]; then
  echo "PASS render smoke-test"
  exit 0
else
  echo "FAIL render smoke-test (see /tmp/tg_selftest.png)"
  exit 1
fi
