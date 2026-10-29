import AppKit

/// Windows are created by `NSDocumentController`, which opens an untitled
/// document at launch and when the Dock icon is clicked with no windows open.
/// The project windows open at quit are opened again at launch, showing the
/// files they showed, and so are the files open in windows of their own,
/// instead of the untitled document. macOS would restore the windows itself
/// only with "Close windows when quitting an application" turned off.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Where the open projects are remembered.
    var settings = Settings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        DevelopmentIcon.install()
        reopenProjects()
        reopenDocuments()
        NSApp.activate()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        projects.isEmpty && !settings.openProjects.contains { Self.exists($0.folder, isFolder: true) }
            && !settings.openDocuments.contains { Self.exists($0, isFolder: false) }
    }

    // Quitting leaves windows open rather than closing them, so the project
    // windows are all still here.
    func applicationWillTerminate(_ notification: Notification) {
        settings.openProjects = projects.map { Settings.OpenProject(folder: $0.root, file: $0.currentDocument?.fileURL) }
        settings.openDocuments = Self.windowedFiles(in: NSApp.orderedWindows)
    }

    /// The files shown in windows of their own among `windows`, in their
    /// order. Untitled documents and those in project windows aren't.
    static func windowedFiles(in windows: [NSWindow]) -> [URL] {
        windows.compactMap { window in
            guard window.windowController is DocumentWindowController else { return nil }
            return (window.windowController?.document as? NSDocument)?.fileURL
        }
    }

    /// Opens the files that were open in windows of their own at quit,
    /// skipping files that have gone. The frontmost is opened last, so it
    /// ends up in front.
    func reopenDocuments() {
        for file in settings.openDocuments.reversed() where Self.exists(file, isFolder: false) {
            NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, _ in }
        }
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
