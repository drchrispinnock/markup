import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Launched from `swift run` there is no app bundle, so the process must ask
// to be a regular app to get a Dock icon, a menu bar and focus.
app.setActivationPolicy(.regular)
app.run()
