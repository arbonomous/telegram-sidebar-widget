# SidePiece

A sleek, screen-docked Telegram widget for macOS. It lives as an unobtrusive strip on the edge of your screen and expands into a full chat panel on cursor hover — no Telegram API credentials required.

It wraps **Telegram Web** (`web.telegram.org/k`) inside a native `WKWebView`, providing persistent login, full sending/receiving capabilities, and seamless integration with macOS.

---

## Features

- **Dock to Either Screen Edge:** Pinned to either the **right** or **left** screen edge with multi-monitor awareness.
- **Rail Style (Classic Telegram Blue):** Solid brand-blue (`#3390EC`-equivalent) collapsed strip with the official Telegram logo, sitting on a dark-neutral floating panel backdrop that prevents visual flashes against any wallpaper.
- **Hover to Expand:** The panel smoothly animates open with an eased transition and collapses back when your cursor moves away.
- **Screen-Edge Unread Badge:** Shows a notification badge pill directly on the collapsed rail when unread messages arrive, plus menu bar status updates.
- **Modern Floating Aesthetic:** 14pt rounded corner radii on the floating inner edges with dark-neutral backdrop to prevent flashes.
- **Native Telegram Day & Night Modes:** Zero artificial CSS hacks — Telegram Web K's official themes (Day and Night Mode) run completely natively and persist automatically.
- **External Link Interception:** Clicking links inside chats opens them in your default browser (Safari, Chrome, etc.) rather than navigating away inside the widget.
- **Full macOS Clipboard Support:** First-class support for standard shortcuts (`Cmd+C`, `Cmd+V`, `Cmd+X`, `Cmd+A`, `Cmd+Z`) inside message inputs.
- **Display & Resolution Awareness:** Automatically repositions when plugging into external monitors or changing display resolutions.
- **Configurable Geometry:**
  - **Panel Width:** Narrow (300pt), Medium (380pt), or Wide (460pt).
  - **Compact Mode:** Center-docked compact sidebar with Short (400pt), Medium (500pt), or Tall (650pt) options.
- **Menu Bar Controls & Shortcuts:**
  - `Cmd+E`: Expand / Collapse Panel
  - `Cmd+H`: Hide / Show SidePiece
  - `Cmd+R`: Reload Web View
  - `Cmd+Q`: Quit SidePiece
  - Launch at Login and Expand on Notification preferences.

---

## Requirements

- macOS 12.0+
- Xcode Command Line Tools (`swiftc`): `xcode-select --install`

---

## Building & Installing

You can use standard `make` or `bash build.sh`:

```bash
make            # Compiles and bundles build/SidePiece.app
make install    # Builds and installs to /Applications/SidePiece.app
make test       # Runs the automated test harness
make dmg        # Packages dist/SidePiece.dmg for distribution
make clean      # Cleans all build artifacts
```

Or via shell scripts directly:

```bash
bash build.sh          # Full build + package + install
bash build.sh --dmg    # Rebuild dist/SidePiece.dmg
```

---

## Project Structure

```
├── Makefile                # Standard developer targets (build, install, test, dmg, clean)
├── build.sh                # Main build and distribution orchestrator
├── Logo.png                # Official Telegram logo loaded onto the collapsed rail
├── Logo.svg                # Vector source for rail branding
├── SidePiece.svg           # High-resolution vector source for the application icon
├── Sources/
│   ├── AppDelegate.swift   # Window controller, geometry, status menu, navigation & link delegate
│   ├── main.swift          # Application entry point with standard Edit menu clipboard bindings
│   ├── build.sh            # Swift compiler invocation (swiftc -O)
│   ├── bundle.sh           # Packages the .app bundle with icons and LaunchAgent resources
│   ├── build-icon.sh       # Compiles AppIcon.icns from SidePiece.svg
│   ├── dmg.sh              # Stages and creates distributable DMG disk image
│   └── com.sidepiece.app.plist # LaunchAgent template for login auto-start
├── Tests/
│   ├── backtest.swift      # Deterministic geometry and badge parsing test suite (29 tests)
│   └── render_smoke.sh     # Headless rendering smoke test for continuous verification
```

---

## License

MIT — see [LICENSE](LICENSE).
