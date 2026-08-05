import CoreGraphics
import Cocoa

let main = CGMainDisplayID()
let b = CGDisplayBounds(main)
print("CGDisplayBounds: x=\(b.origin.x) y=\(b.origin.y) w=\(b.size.width) h=\(b.size.height)")

if let screen = NSScreen.main {
    let f = screen.frame
    print("NSScreen.main.frame: x=\(f.origin.x) y=\(f.origin.y) w=\(f.size.width) h=\(f.size.height)")
    print("NSScreen.main.backingScaleFactor=\(screen.backingScaleFactor)")
}

// What mouseLocation reports (logical points) vs where the panel would be placed.
let mouse = NSEvent.mouseLocation
print("NSEvent.mouseLocation (logical points): x=\(mouse.x) y=\(mouse.y)")

// Reproduce AppDelegate's collapsed placement math using CGDisplayBounds:
let screenMaxX = CGFloat(b.maxX)
let collapsedX = screenMaxX - 40
print("AppDelegate would place collapsed strip at logical x=\(collapsedX) (w=40)")
print("AppDelegate nearRightEdge threshold (mouse.x >= \(screenMaxX - 70)) -- achievable with mouse max ~\(mouse.x)? \(mouse.x >= screenMaxX - 70)")
