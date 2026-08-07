# SidePiece

A screen-docked Telegram widget for macOS. It lives as a thin strip on the
**right screen edge** and expands into a full chat panel when you hover it —
no Telegram API credentials required.

It wraps **Telegram Web** (`web.telegram.org/k`) inside a native `WKWebView`,
so sending, receiving, and read state all work, and your login persists
between launches.

## Features

- **Dock to the right edge.** A 40px collapsed strip with a solid Telegram
  brand-blue (`#3390EC`) background and the official Telegram logo at the top.
- **Hover to expand.** The panel smoothly grows to 380px with an eased
  transition; it collapses back when the cursor leaves.
- **Real Telegram Web.** Login via QR / phone number inside the panel — your
  session is preserved across relaunches.
- **Light theme.** The web view is forced to Telegram's clean light theme
  (white surfaces, brand-blue accents).
- **Accessory app.** Runs as a menu-bar / background accessory (no Dock icon),
  so it stays out of the way until you need it.

## Requirements

- macOS 12.0+
- Xcode Command Line Tools (`swiftc`): `xcode-select --install`

## Build

```bash
cd web
./build.sh          # produces ../SidePiece (a runnable binary)
```

## Run (from source)

```bash
./SidePiece
```

- Hover the strip on the right edge → it expands.
- Move the cursor away → it collapses.
- First launch: log into Telegram Web inside the panel.

## Package as a real .app (Login Item)

```bash
cd web
./bundle.sh          # produces ../SidePiece.app
```

Move `SidePiece.app` to `/Applications`. To have it start automatically at
login (and relaunch if it crashes), install the bundled LaunchAgent:

```bash
cp web/com.sidepiece.app.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.sidepiece.app.plist
```

The bundle copies the official `Logo.png` next to the executable; the rail
loads it at runtime. (Bundle resource lookup was unreliable in this project,
so the logo is loaded from an explicit file path.)

**Session persistence:** the WebView's data store is pinned to a fixed
identifier (`WKWebsiteDataStore(forIdentifier:)`), so your Telegram login
survives app renames, rebuilds, and reinstalls — log in once and stay logged
in. The first launch migrates any session left behind by the old
`TelegramSidebarWeb` build.

## Distribute as a DMG

```bash
bash web/dmg.sh          # builds the .app, then ./SidePiece.dmg
```

Send `SidePiece.dmg` to a friend — they open it and drag
`SidePiece.app` into Applications.

## Tests

```bash
xcrun swift Tests/backtest.swift        # logic harness (badge, hover, geometry)
bash Tests/render_smoke.sh              # renders the WebView and proves it isn't blank
```

`render_smoke.sh` launches the app in `--selftest` mode, which force-expands
the panel, captures the rendered pixels, and fails if the WebView paints
blank/white (the regression that once shipped undetected). Requires network
access and a window server (run on a logged-in Mac, not headless CI).

## Project layout

```
web/
  AppDelegate.swift   # panel, rail, hover/animation, Telegram-Web bridge, --selftest
  main.swift          # NSApplication entry point (accessory policy)
  build.sh            # swiftc build
  bundle.sh           # package as .app (icon + logo)
  dmg.sh              # package as distributable .dmg
  Logo.png            # official Telegram logo (rendered on the collapsed rail)
build/AppIcon.icns    # app icon (generated from Logo.png)
Logo.svg              # vector source for the logo
Tests/
  backtest.swift      # end-to-end logic harness (20/20 checks)
  render_smoke.sh     # render smoke-test (catches blank/white regressions)
```

## How it works

- The panel is a borderless, non-activating `NSPanel` pinned to the right edge.
- A 40px `railView` holds the brand-blue background + logo; it is removed from
  the view hierarchy whenever the panel is expanded, so the blue never shows
  across a wide panel.
- The `WKWebView` loads `web.telegram.org/k` directly and is **opaque**
  (`drawsBackground = true`) so Telegram's own content always paints reliably
  inside a borderless panel. It is explicitly un-hidden on every expand.
- An injected script forces Telegram's light theme and keeps it applied.
- Hover is polled via `NSEvent.mouseLocation` (no Accessibility permission
  required), driving a smooth `easeInEaseOut` expand/collapse.

## License

MIT — see [LICENSE](LICENSE).
