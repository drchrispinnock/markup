import AppKit

/// Windows are created by `NSDocumentController`, which opens an untitled
/// document at launch and when the Dock icon is clicked with no windows open.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        NSApp.activate()
    }
}
