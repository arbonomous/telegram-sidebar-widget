import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.regular)   // normal app: owns a Dock tile that shows the "open" indicator
let delegate = AppDelegate.shared
app.delegate = delegate
app.run()
