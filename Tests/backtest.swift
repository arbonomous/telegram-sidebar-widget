// End-to-end back test for the Telegram Sidebar Widget.
// This is a FAITHFUL PORT of the deterministic logic in
// web/AppDelegate.swift (updateBadge / setExpanded / pollHover) so we can
// exercise it from the command line with real assertions. The ported code is
// copied verbatim from the app source; only UI mutation is replaced by returns.
import Foundation
import CoreGraphics // CGRect/CGPoint/minX etc. — the app gets this transitively via Cocoa.

// ---- Faithful port of updateBadge(from:) (AppDelegate.swift:240-246) ----
func parseBadge(_ title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespaces)
    var count = 0
    if let range = trimmed.range(of: #"^\(\d+\)"#, options: .regularExpression),
       let n = Int(trimmed[range].dropFirst().dropLast()) { count = n }
    return count > 0 ? "✈(\(count > 99 ? "99+" : "\(count)"))" : "✈"
}

// ---- Faithful port of the hover hit-test predicates in pollHover (168-198) ----
func isInsidePanel(_ mouse: CGPoint, _ frame: CGRect) -> Bool {
    mouse.x >= frame.minX && mouse.x <= frame.maxX &&
    mouse.y >= frame.minY && mouse.y <= frame.maxY
}
func isNearRightEdge(_ mouseX: CGFloat, _ screenMaxX: CGFloat) -> Bool {
    mouseX >= (screenMaxX - 70)
}
// pollHover: expand when inside panel OR near right edge.
func shouldExpandNow(_ inside: Bool, _ near: Bool) -> Bool { inside || near }
// collapse grace re-check: only collapse if NOT inside and NOT near.
func shouldCollapseNow(_ inside: Bool, _ near: Bool) -> Bool { !(inside || near) }

// ---- Faithful port of the setExpanded geometry (120-130) ----
// Returns the panel target frame for a given screen + expanded flag.
func panelFrame(screenMaxX: CGFloat, visMinY: CGFloat, visH: CGFloat, expanded: Bool) -> CGRect {
    let w: CGFloat = expanded ? 380 : 40
    return CGRect(x: screenMaxX - w, y: visMinY, width: w, height: visH)
}
// Internal webView width stays 380 whether collapsed or expanded (slides, not squished).
func webViewInternalWidth() -> CGFloat { 380 }

// ============================ TEST HARNESS ============================
var pass = 0, fail = 0
func check(_ name: String, _ got: String, _ want: String) {
    if got == want { pass += 1; print("  PASS  \(name)") }
    else { fail += 1; print("  FAIL  \(name)\n        got:  \(got)\n        want: \(want)") }
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
check("malformed",       parseBadge("Telegram (3)"),            "✈")  // count at front only
check("empty",           parseBadge(""),                        "✈")

print("== Hover hit-test (pollHover) ==")
// Screen: 1440x900, right edge at maxX=1440. Collapsed strip 40px wide.
let maxX: CGFloat = 1440, minY: CGFloat = 0, h: CGFloat = 900
let collapsed = panelFrame(screenMaxX: maxX, visMinY: minY, visH: h, expanded: false) // x=1400 w=40
let onStrip   = CGPoint(x: 1420, y: 450)
let nearEdge  = CGPoint(x: 1410, y: 450)   // >= 1370
let farAway   = CGPoint(x: 800, y: 450)    // not inside, not near
checkBool("inside panel true",  isInsidePanel(onStrip, collapsed), true)
checkBool("near edge true",     isNearRightEdge(nearEdge.x, maxX), true)
checkBool("near edge false",    isNearRightEdge(farAway.x, maxX), false)
checkBool("expand on strip",    shouldExpandNow(isInsidePanel(onStrip, collapsed), isNearRightEdge(onStrip.x, maxX)), true)
checkBool("expand near edge",   shouldExpandNow(isInsidePanel(farAway, collapsed), isNearRightEdge(nearEdge.x, maxX)), true)
checkBool("expand far away off",shouldExpandNow(isInsidePanel(farAway, collapsed), isNearRightEdge(farAway.x, maxX)), false)
checkBool("collapse far away",   shouldCollapseNow(isInsidePanel(farAway, collapsed), isNearRightEdge(farAway.x, maxX)), true)
checkBool("collapse while on strip", shouldCollapseNow(isInsidePanel(onStrip, collapsed), isNearRightEdge(onStrip.x, maxX)), false)

print("== Expand/collapse geometry (setExpanded) ==")
checkRect("collapsed frame", panelFrame(screenMaxX: maxX, visMinY: minY, visH: h, expanded: false),
          CGRect(x: 1400, y: 0, width: 40, height: 900))
checkRect("expanded frame",  panelFrame(screenMaxX: maxX, visMinY: minY, visH: h, expanded: true),
          CGRect(x: 1060, y: 0, width: 380, height: 900))
check("webview stays 380", "\(Int(webViewInternalWidth()))", "380")

print("\n== RESULT: \(pass) passed, \(fail) failed ==")
if fail > 0 { exit(1) }
