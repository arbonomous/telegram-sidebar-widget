# Telegram Sidebar Widget

A screen-docked Telegram widget for macOS. It collapses to a thin strip on the
left/right screen edge and pops out when you hover it — or when a new message
arrives. No Telegram API credentials needed: it wraps **Telegram Web**
(`web.telegram.org/k`) in a native WebView, so send/receive/read all work and
your login persists between launches.

## Build
Requires Xcode Command Line Tools:
```bash
xcode-select --install      # only if swiftc is missing
./build.sh
```

## Run
```bash
./telegram-sidebar
```
- Hover the strip on the screen edge → it expands.
- Move the cursor away → it collapses after a few seconds.
- **Double-click** the panel → pins it open (won't auto-collapse). Double-click again to unpin.
- **Right-click** the panel → menu to switch edge, toggle auto-expand-on-message, or quit.
- First time: log into Telegram Web inside the panel.

## Package as a real app + login item
```bash
./bundle.sh                       # -> TelegramSidebar.app
# move to /Applications, add to System Settings ▸ Login Items
# or use the LaunchAgent plist in this folder
```

## Settings
Config lives at `~/Library/Application Support/TelegramSidebar/config.json`:
```json
{
  "edge": "right",
  "collapsedWidth": 34,
  "expandedWidth": 380,
  "autoCollapseDelay": 3.0,
  "autoExpandOnMessage": true
}
```
Edit and relaunch. (You can also flip edge / auto-expand from the right-click menu.)

## How the "new message" pop-out works
The widget polls the WebView's page title once per second. Telegram Web mirrors
the unread count into the title (e.g. `(3) Telegram`), exactly like a browser
tab badge. When that count rises while collapsed, the widget expands to notify
you and shows the red unread badge on the strip.
