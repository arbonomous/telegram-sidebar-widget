import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar / accessory only, no Dock icon
let delegate = AppDelegate.shared
app.delegate = delegate
app.run()
