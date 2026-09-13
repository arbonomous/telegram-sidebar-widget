// End-to-end back test for the SidePiece widget.
// This is a FAITHFUL PORT of the deterministic logic in
// Sources/AppDelegate.swift so we can exercise it from the command line
// with real assertions. The ported code is copied verbatim from the app
// source; only UI mutation is replaced by returns.
import Foundation
import CoreGraphics // CGRect/CGPoint/minX etc.

// ---- Faithful port of updateBadge(from:) (AppDelegate.swift) ----
func parseBadge(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespaces)
    var count = 0
    if let range = trimmed.range(of: #"^\(\d+\)"#, options: .regularExpression),
       let n = Int(trimmed[range].dropFirst().dropLast()) { count = n }
    return count > 0 ? "✈(\(count > 99 ? "99+" : "\(count)"))" : "✈"
}

// ---- Faithful port of hover hit-test (pollHover) ----
// Current behavior: expand ONLY when the cursor is over the actual panel
// frame. No preemptive edge buffer.
func isInsidePanel(_ mouse: CGPoint, _ frame: CGRect) -> Bool {
    mouse.x >= frame.minX && mouse.x <= frame.maxX &&
    mouse.y >= frame.minY && mouse.y <= frame.maxY
}
func shouldExpandNow(_ inside: Bool) -> Bool { inside }
func shouldCollapseNow(_ inside: Bool) -> Bool { !inside }

// ---- Faithful port of geometry helpers ----
enum DockSide { case left, right }
func panelFrame(sideOrigin: CGFloat, visMinY: CGFloat, visH: CGFloat,
                dockSide: DockSide, expanded: Bool, edgeInset: CGFloat = 6, compactMode: Bool = true, compactHeight: CGFloat = 500) -> CGRect {
    let w: CGFloat = expanded ? 380 : 40
    let h: CGFloat = compactMode ? min(compactHeight, visH) : visH
    let yOrigin: CGFloat = compactMode ? visMinY + (visH - h) / 2.0 : visMinY
    let xOrigin: CGFloat
    switch dockSide {
    case .right:
        xOrigin = sideOrigin - w - edgeInset
    case .left:
        xOrigin = sideOrigin
    }
    return CGRect(x: xOrigin, y: yOrigin, width: w, height: h)
}
func webViewInternalWidth() -> CGFloat { 380 }

// ============================ TEST HARNESS ============================
var pass = 0, fail = 0
func check(_ name: String, _ got: String, _ want: String) {
    if got == want { pass += 1; print("  PASS  \(name)") }
    else { fail += 1; print("  FAIL  \(name)\n        got:  \(got)\n        want:  \(want)") }
}
func checkBool(_ name: String, _ got: Bool, _ want: Bool) {
    if got == want { pass += 1; print("  PASS  \(name)") }
    else { fail += 1; print("  FAIL  \(name) got=\(got) want=\(want)") }
}
func checkRect(_ name: String, _ got: CGRect, _ want: CGRect) {
    let approx = { (a: CGFloat, b: CGFloat) in abs(a - b) < 0.001 }
    let eq = approx(got.origin.x, want.origin.x) && approx(got.origin.y, want.origin.y) &&
             approx(got.size.width, want.size.width) && approx(got.size.height, want.size.height)
    if eq { pass += 1; print("  PASS  \(name)") }
    else { fail += 1; print("  FAIL  \(name) got=\(got) want=\(want)") }
}

print("== Badge title parsing (updateBadge) ==")
check("unread 3",        parseBadge("(3) Telegram"),            "✈(3)")
check("unread 1",        parseBadge("(1) Telegram"),            "✈(1)")
check("no unread",       parseBadge("Telegram"),                "✈")
check("zero unread",     parseBadge("(0) Telegram"),            "✈")
check("over 99 capped",  parseBadge("(100) Telegram"),          "✈(99+)")
check("two digits",      parseBadge("(12) Telegram"),           "✈(12)")
check("leading spaces",  parseBadge("  (5) Telegram"),          "✈(5)")
check("malformed",       parseBadge("Telegram (3)"),            "✈")
check("empty",           parseBadge(""),                        "✈")

print("== Hover hit-test (pollHover) ==")
// Screen: 1440x900, right edge at maxX=1440. Collapsed strip 40px wide, inset 6px.
let maxX: CGFloat = 1440, minY: CGFloat = 0, h: CGFloat = 900
let collapsedRight = panelFrame(sideOrigin: maxX, visMinY: minY, visH: h, dockSide: .right, expanded: false)
let onStrip   = CGPoint(x: 1415, y: 450)
let farAway   = CGPoint(x: 800, y: 450)
checkBool("inside panel true",  isInsidePanel(onStrip, collapsedRight), true)
checkBool("inside panel false", isInsidePanel(farAway, collapsedRight), false)
checkBool("expand on strip",    shouldExpandNow(isInsidePanel(onStrip, collapsedRight)), true)
checkBool("expand far away off",shouldExpandNow(isInsidePanel(farAway, collapsedRight)), false)
checkBool("collapse far away",   shouldCollapseNow(isInsidePanel(farAway, collapsedRight)), true)
checkBool("collapse while on strip", shouldCollapseNow(isInsidePanel(onStrip, collapsedRight)), false)

// Left dock: panel anchored at display.minX.
let leftDockX: CGFloat = 0
let collapsedLeft = panelFrame(sideOrigin: leftDockX, visMinY: minY, visH: h, dockSide: .left, expanded: false)
let onLeftStrip = CGPoint(x: 20, y: 450)
checkBool("left dock inside",     isInsidePanel(onLeftStrip, collapsedLeft), true)
checkBool("left dock far away",   isInsidePanel(farAway, collapsedLeft), false)
checkBool("left dock expand",     shouldExpandNow(isInsidePanel(onLeftStrip, collapsedLeft)), true)
checkRect("left dock frame",      collapsedLeft, CGRect(x: 0, y: 200, width: 40, height: 500))
checkRect("right dock frame",     collapsedRight, CGRect(x: 1394, y: 200, width: 40, height: 500))

print("== Expand/collapse geometry (setExpanded) ==")
checkRect("right collapsed", panelFrame(sideOrigin: maxX, visMinY: minY, visH: h, dockSide: .right, expanded: false),
          CGRect(x: 1394, y: 200, width: 40, height: 500))
checkRect("right expanded",  panelFrame(sideOrigin: maxX, visMinY: minY, visH: h, dockSide: .right, expanded: true),
          CGRect(x: 1054, y: 200, width: 380, height: 500))
checkRect("left collapsed",  panelFrame(sideOrigin: 0, visMinY: minY, visH: h, dockSide: .left, expanded: false),
          CGRect(x: 0, y: 200, width: 40, height: 500))
checkRect("left expanded",  panelFrame(sideOrigin: 0, visMinY: minY, visH: h, dockSide: .left, expanded: true),
          CGRect(x: 0, y: 200, width: 380, height: 500))
check("webview stays 380", "\(Int(webViewInternalWidth()))", "380")

print("== Compact sidebar mode ==")
// 900pt tall screen, compactHeight=500 -> centered at y=200
checkRect("compact right collapsed",
          panelFrame(sideOrigin: maxX, visMinY: minY, visH: h, dockSide: .right, expanded: false, compactMode: true),
          CGRect(x: 1394, y: 200, width: 40, height: 500))
checkRect("compact right expanded",
          panelFrame(sideOrigin: maxX, visMinY: minY, visH: h, dockSide: .right, expanded: true, compactMode: true),
          CGRect(x: 1054, y: 200, width: 380, height: 500))
checkRect("compact left collapsed",
          panelFrame(sideOrigin: 0, visMinY: minY, visH: h, dockSide: .left, expanded: false, compactMode: true),
          CGRect(x: 0, y: 200, width: 40, height: 500))
// Short screen: 400px tall, compact caps to 400 -> centered at y=0
checkRect("compact right collapsed on short screen",
          panelFrame(sideOrigin: maxX, visMinY: minY, visH: 400, dockSide: .right, expanded: false, compactMode: true),
          CGRect(x: 1394, y: 0, width: 40, height: 400))

print("\n== RESULT: \(pass) passed, \(fail) failed ==")
if fail > 0 { exit(1) }
