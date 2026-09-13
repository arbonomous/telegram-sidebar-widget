# SidePiece — Tester's Guide

Thank you for testing **SidePiece**, a screen-docked Telegram widget for macOS.

---

## 1. Installation & The "Damaged App" Warning

### Why macOS shows *"SidePiece is damaged and can't be opened"*:
When you download apps outside the Mac App Store (via Telegram, Safari, Chrome, AirDrop, etc.), macOS automatically attaches a security flag called `com.apple.quarantine`.

Because SidePiece is an independent project without a paid Apple Developer certificate ($99/year), modern macOS (Ventura, Sonoma, Sequoia) shows the alert:
> *"SidePiece is damaged and can't be opened. You should move it to the Trash."*

**The app is NOT damaged.** It is safe and intact.

---

### How to Install & Open (100% GUI — No Terminal Needed)

#### Option 1: Native macOS Installer Package (Easiest & Recommended)
Use the included **`SidePiece.pkg`** installer:
1. Double-click **`SidePiece.pkg`**.
2. If macOS prompts that the package is from an unidentified developer:
   - **Right-Click (or Control-Click) `SidePiece.pkg` -> click `Open`**.
   - (Or in **System Settings -> Privacy & Security**, scroll down and click **Open Anyway**).
3. Follow the on-screen installer steps. It automatically places `SidePiece.app` into `/Applications` and removes the quarantine flag.
4. Open **SidePiece** from your Applications folder or Launchpad!

---

#### Option 2: The Control-Click Bypass (For `SidePiece.app`)
If you already have `SidePiece.app` in `/Applications`:
1. Make sure `SidePiece.app` is in your **Applications** folder (if you accidentally clicked *"Move to Trash"*, open Trash and drag it back to Applications).
2. **Hold the `Control` key on your keyboard and click `SidePiece.app`** (or **Right-Click** it).
3. Select **Open** from the menu.
4. A confirmation dialog will appear. Click **Open**.
5. *Note for macOS Sequoia (macOS 15):* If the alert still says damaged, click **Done** (do NOT click Move to Trash), then immediately open **System Settings -> Privacy & Security**, scroll down to Security, click **Open Anyway**, and confirm with **Open**.

---

## 2. What to Test

### Docking & Hover Expand
- **Docked Rail:** A 40px blue strip with the Telegram logo is pinned to the right edge of your screen.
- **Hover Expand:** Move your cursor over the rail — it smoothly slides open.
- **Hover Collapse:** Move your cursor away — after a brief grace period, it smoothly docks back to the edge.

### Telegram Web & Login
- Scan the QR code or log in with your phone number.
- Test sending and receiving messages.
- Test clipboard shortcuts: `Cmd + C`, `Cmd + V`, `Cmd + A`, `Cmd + Z`.
- External web links open in your default browser (Safari, Chrome) rather than inside the widget.

### Unread Notification Badges
- When someone sends you a message while SidePiece is collapsed:
  - A red notification badge pill appears on the screen rail below the logo.
  - The menu bar icon displays the unread count.
  - A native macOS notification banner appears.

### Day & Night Theme
- In the sidebar, click the top-left Telegram menu (`☰`).
- Toggle **Night Mode**: Telegram Web natively adapts to official dark mode without visual glitches.

### Menu Bar Controls
Click the **Telegram icon** in the macOS menu bar:
- **Dock Side:** Switch between **Right** and **Left** screen edges.
- **Panel Width:** Choose **Narrow (300pt)**, **Medium (380pt)**, or **Wide (460pt)**.
- **Compact Sidebar:** Toggles center-docked compact height (**Short 400pt**, **Medium 500pt**, **Tall 650pt**).
- **Keyboard Shortcuts:**
  - `Cmd + E`: Expand / Collapse Panel
  - `Cmd + H`: Hide / Show SidePiece
  - `Cmd + R`: Reload Telegram Web
  - `Cmd + Q`: Quit SidePiece
- **Launch at Login:** Auto-start SidePiece on Mac login.
