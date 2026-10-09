import AppKit

// Bootstrap: one window, no storyboard, no account, zero network calls.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
