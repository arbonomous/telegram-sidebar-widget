import Quartz
from Foundation import NSURL

did = Quartz.CGMainDisplayID()
img = Quartz.CGDisplayCreateImage(did)
if img is None:
    print("NO_ACCESS")
    raise SystemExit(2)

w = Quartz.CGImageGetWidth(img)
h = Quartz.CGImageGetHeight(img)
print("full:", w, "x", h)

# Physical display width is 2x logical. Collapsed strip lives at logical x=1400 (w=40).
# Capture logical 1360..1440 -> physical 2720..2880 to include the near-edge hover zone.
scale = w / 1440.0
cx = int(1360 * scale)
cw = int((1440 - 1360) * scale)
rect = Quartz.CGRectMake(cx, 0, cw, h)
strip = Quartz.CGImageCreateWithImageInRect(img, rect)
if strip is None:
    print("CROP_FAIL")
    raise SystemExit(3)

url = NSURL.fileURLWithPath_("/tmp/edge.png")
dest = Quartz.CGImageDestinationCreateWithURL(url, "public.png", 1, None)
Quartz.CGImageDestinationAddImage(dest, strip, None)
ok = Quartz.CGImageDestinationFinalize(dest)
print("saved /tmp/edge.png", "finalize=", ok, "size", cw, "x", h)
