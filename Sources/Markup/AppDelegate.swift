import AppKit

/// Windows are created by `NSDocumentController`, which opens an untitled
/// document at launch and when the Dock icon is clicked with no windows open.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        DevelopmentIcon.install()
        NSApp.activate()
    }

    private var settingsWindowController: SettingsWindowController?

    /// Markup > Settings.
    @objc func showSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: .shared)
        }
        settingsWindowController?.showWindow(sender)
    }
}
