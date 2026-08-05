import Quartz, time
from Foundation import NSURL

# Use the AX/CG window list API to find the actual on-screen window rect of the widget,
# independent of what the code thinks it set.
opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
win_list = Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID)
targets = []
for w in win_list:
    name = w.get("kCGWindowName", "")
    owner = w.get("kCGWindowOwnerName", "")
    pid = w.get("kCGWindowOwnerPID", 0)
    if "TelegramSidebar" in owner or "TelegramSidebar" in name or pid == 80294:
        targets.append(w)
print("=== widget windows found on screen:", len(targets))
for w in targets:
    print("  owner=", w.get("kCGWindowOwnerName"), "name=", repr(w.get("kCGWindowName")),
          "pid=", w.get("kCGWindowOwnerPID"), "bounds=", w.get("kCGWindowBounds"))
if not targets:
    print("  NONE — the panel is NOT on any screen (ordered out, zero-size, or off-screen frame).")

# Also dump the largest window bounds per PID for the widget to see what's there.
print("\n=== all TelegramSidebar processes (ps) ===")
import subprocess
print(subprocess.run(["pgrep","-fl","TelegramSidebarWeb"], capture_output=True, text=True).stdout)
