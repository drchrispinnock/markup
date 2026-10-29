import AppKit

/// File > Open Recent: the recent files (`NSDocumentController`'s list), then
/// the recent projects (`Settings.recentProjects`), then Clear Menu. The menu
/// is built here rather than by AppKit, because AppKit's own would open a
/// project folder as a document.
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let files = NSDocumentController.shared.recentDocumentURLs
        let projects = settings.recentProjects.filter {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        for url in files {
            menu.addItem(recentItem(for: url, action: #selector(openRecentDocument(_:))))
        }
        if !files.isEmpty && !projects.isEmpty {
            menu.addItem(.separator())
        }
        for url in projects {
            menu.addItem(recentItem(for: url, action: #selector(openRecentProject(_:))))
        }
        if !files.isEmpty || !projects.isEmpty {
            menu.addItem(.separator())
        }
        let clear = menu.addItem(withTitle: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !files.isEmpty || !projects.isEmpty
    }

    private func recentItem(for url: URL, action: Selector) -> NSMenuItem {
        let name = FileManager.default.displayName(atPath: url.path)
        let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
        // The folder it is in follows its name, dimmed, since many have the
        // same name (every Leanpub book's folder is "manuscript").
        let title = NSMutableAttributedString(string: name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        title.append(NSAttributedString(string: "  " + Self.recentLocation(of: url), attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        item.attributedTitle = title
        item.target = self
        item.representedObject = url
        item.toolTip = url.path
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        item.image = icon
        return item
    }

    /// The folder `url` is in, as Open Recent shows it: from "~" when in the
    /// home folder, and with the middle left out when long, keeping the end,
    /// which tells most.
    static func recentLocation(of url: URL, home: String = NSHomeDirectory(), maxLength: Int = 50) -> String {
        var path = url.deletingLastPathComponent().path
        if path == home || path.hasPrefix(home + "/") {
            path = "~" + path.dropFirst(home.count)
        }
        guard path.count > maxLength else { return path }
        let tail = (maxLength - 1) * 2 / 3
        return path.prefix(maxLength - 1 - tail) + "…" + path.suffix(tail)
    }

    @objc func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    @objc func openRecentProject(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openProject(at: url)
    }

    @objc func clearRecent(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
        settings.recentProjects = []
    }
}
