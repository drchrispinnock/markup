import AppKit

/// Windows are created by `NSDocumentController`, which opens an untitled
/// document at launch and when the Dock icon is clicked with no windows open.
/// The project windows open at quit are opened again at launch, showing the
/// files they showed, instead of the untitled document.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Where the open projects are remembered.
    var settings = Settings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        DevelopmentIcon.install()
        reopenProjects()
        NSApp.activate()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        projects.isEmpty && !settings.openProjects.contains { Self.exists($0.folder, isFolder: true) }
    }

    // Quitting leaves windows open rather than closing them, so the project
    // windows are all still here.
    func applicationWillTerminate(_ notification: Notification) {
        settings.openProjects = projects.map { Settings.OpenProject(folder: $0.root, file: $0.currentDocument?.fileURL) }
    }

    /// Opens the projects that were open at quit, with the files they showed,
    /// skipping folders and files that have gone.
    func reopenProjects() {
        for saved in settings.openProjects where Self.exists(saved.folder, isFolder: true) {
            let project = openProject(at: saved.folder)
            if let file = saved.file, Self.exists(file, isFolder: false) {
                project.open(file)
            }
        }
    }

    private static func exists(_ url: URL, isFolder: Bool) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue == isFolder
    }

    let updater = Updater()

    /// Markup > Check for Updates.
    @objc func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates()
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
        panel.message = "Choose a folder to browse its Markdown and text files."
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
        settings.noteRecentProject(folder)
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

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(checkForUpdates(_:)) ? updater.canCheckForUpdates : true
    }
}
