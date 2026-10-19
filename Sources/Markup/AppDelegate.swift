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

    /// The open project windows.
    private(set) var projects: [ProjectWindowController] = []

    /// File > Open Project: chooses a folder and opens it in a project window.
    @objc func openProject(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.message = "Choose a folder to browse its Markdown files."
        panel.prompt = "Open Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    /// Opens a project window for `folder`, or brings forward the one already
    /// open for it.
    @discardableResult
    func openProject(at folder: URL) -> ProjectWindowController {
        if let open = projects.first(where: { $0.root == folder.standardizedFileURL }) {
            open.showWindow(nil)
            return open
        }
        let project = ProjectWindowController(root: folder)
        project.onClose = { [unowned self, unowned project] in projects.removeAll { $0 === project } }
        projects.append(project)
        project.showWindow(nil)
        return project
    }
}
