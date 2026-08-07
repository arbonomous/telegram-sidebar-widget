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

## Build & install

```bash
bash build.sh          # build + bundle .app, install to /Applications,
                       # auto-launch at login, rebuild dist/SidePiece.dmg
```

- `bash build.sh --icon` — also regenerate the icon from `SidePiece.svg`
- `bash build.sh --dmg`   — only rebuild `dist/SidePiece.dmg` from the existing `.app`

After install, hover the strip on the right edge → it expands; move the cursor
away → it collapses. First launch: log into Telegram Web inside the panel.

The bundle copies the official `Logo.png` next to the executable; the rail
loads it at runtime. (Bundle resource lookup was unreliable in this project,
so the logo is loaded from an explicit file path.)

**Session persistence:** the WebView's data store is pinned to a fixed
identifier (`WKWebsiteDataStore(forIdentifier:)`), so your Telegram login
survives app renames, rebuilds, and reinstalls — log in once and stay logged
in. The first launch migrates any session left behind by the old
`TelegramSidebarWeb` build.

**Single instance:** only one interactive SidePiece may run at a time — a
process-level advisory lock (`~/Library/Application Support/SidePiece/.running`)
blocks a second launch, which previously caused two overlapping widgets/sessions
on the edge. Diagnostic mode (`--selftest`) is exempt so the test harness can
run in parallel.

## Distribute as a DMG

```bash
bash build.sh --dmg     # produces dist/SidePiece.dmg
```

Send `dist/SidePiece.dmg` to a friend — they open it and drag
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
Sources/                  # the Swift app source (not a website)
  AppDelegate.swift       # panel, rail, hover/animation, Telegram-Web bridge, --selftest
  main.swift              # NSApplication entry point (accessory policy)
  build.sh               # swiftc build
  bundle.sh              # package as .app (icon + logo)
  build-icon.sh          # regenerate build/AppIcon.icns from SidePiece.svg
  dmg.sh                 # package as distributable .dmg
  com.sidepiece.app.plist# LaunchAgent (auto-launch at login)
build/                    # regenerable artifacts (git-ignored)
  AppIcon.icns            # app icon (generated from SidePiece.svg)
dist/                     # distributables (git-ignored)
  SidePiece.dmg
Logo.png                  # official Telegram logo (rendered on the collapsed rail)
Logo.svg                  # vector source for the logo
SidePiece.svg             # app-icon source (tracked)
Tests/
  backtest.swift          # end-to-end logic harness (20/20 checks)
  render_smoke.sh         # render smoke-test (catches blank/white regressions)
build.sh                  # one-command front door (build + install + dmg)
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
