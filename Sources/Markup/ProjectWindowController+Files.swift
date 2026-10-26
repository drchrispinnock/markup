import AppKit

/// The sidebar's menu (`ProjectSidebarController.menu`): New File, New
/// Folder, Duplicate, Rename and Delete, for the item clicked, which each menu item
/// carries as its `representedObject`. New items go in the folder clicked,
/// or the folder of the file clicked. Delete moves to the Trash.
extension ProjectWindowController {
    /// Sidebar > New File…: asks for a name, then makes the file and opens it.
    @objc func newFile(_ sender: Any?) {
        let folder = Self.folder(for: clickedURL(sender) ?? root)
        askForName(title: "New File in “\(folder.lastPathComponent)”", defaultName: Self.uniqueName("Untitled", extension: "md", in: folder)) { [weak self] name in
            guard let self else { return }
            run { open(try createFile(named: name, in: folder)) }
        }
    }

    /// Sidebar > New Folder…: asks for a name, then makes the folder.
    @objc func newFolder(_ sender: Any?) {
        let folder = Self.folder(for: clickedURL(sender) ?? root)
        askForName(title: "New Folder in “\(folder.lastPathComponent)”", defaultName: Self.uniqueName("untitled folder", extension: "", in: folder)) {
            [weak self] name in
            guard let self else { return }
            run { sidebar.select(try createFolder(named: name, in: folder)) }
        }
    }

    /// Sidebar > Duplicate: copies the file or folder beside it, and opens
    /// a copied file.
    @objc func duplicateItem(_ sender: Any?) {
        guard let url = clickedURL(sender), url != root else { return }
        run {
            let copy = try duplicate(url)
            if Self.isFolder(copy) { sidebar.select(copy) } else { open(copy) }
        }
    }

    /// Sidebar > Rename…: asks for a new name, starting from the current one.
    @objc func renameItem(_ sender: Any?) {
        guard let url = clickedURL(sender), url != root else { return }
        askForName(title: "Rename “\(url.lastPathComponent)”", defaultName: url.lastPathComponent, button: "Rename") {
            [weak self] name in
            guard let self else { return }
            run { sidebar.select(try rename(url, to: name)) }
        }
    }

    /// Sidebar > Delete: moves the file or folder to the Trash, first asking
    /// if it holds files open here with unsaved changes, which are closed.
    @objc func deleteItem(_ sender: Any?) {
        guard let url = clickedURL(sender), url != root, let window else { return }
        let edited = documents(inside: url).filter(\.isDocumentEdited)
        guard !edited.isEmpty else {
            run { try trash(url) }
            return
        }
        let alert = NSAlert()
        alert.messageText = edited.count == 1 && edited[0].fileURL == url
            ? "“\(url.lastPathComponent)” has unsaved changes. Delete it anyway?"
            : "“\(url.lastPathComponent)” holds files with unsaved changes. Delete it anyway?"
        alert.informativeText = "It goes in the Trash, without the changes."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            run { try trash(url) }
        }
    }

    // MARK: - The operations

    /// Makes an empty file called `name` in `folder`, with ".md" added if
    /// it has no extension, and returns it.
    @discardableResult
    func createFile(named name: String, in folder: URL) throws -> URL {
        let file = folder.appendingPathComponent(try Self.checkedName(name, defaultExtension: "md", in: folder))
        try Data().write(to: file, options: .withoutOverwriting)
        sidebarFolderChanged()
        return file.standardizedFileURL
    }

    /// Makes a folder called `name` in `folder`, and returns it.
    @discardableResult
    func createFolder(named name: String, in folder: URL) throws -> URL {
        let made = folder.appendingPathComponent(try Self.checkedName(name, defaultExtension: nil, in: folder), isDirectory: true)
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: false)
        sidebarFolderChanged()
        return made.standardizedFileURL
    }

    /// Copies `url` beside it, named as Finder names a copy ("a copy.md",
    /// "a copy 2.md"...), and returns the copy.
    @discardableResult
    func duplicate(_ url: URL) throws -> URL {
        let folder = url.deletingLastPathComponent()
        let ext = Self.isFolder(url) ? "" : url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let copy = folder.appendingPathComponent(Self.uniqueName(base + " copy", extension: ext, in: folder))
        try FileManager.default.copyItem(at: url, to: copy)
        sidebarFolderChanged()
        return copy.standardizedFileURL
    }

    /// Renames `url` to `name`, as typed, and returns where it is now. The
    /// documents open here from it follow it, unsaved changes and all.
    /// Links to it from other files are left as they are.
    @discardableResult
    func rename(_ url: URL, to name: String) throws -> URL {
        let folder = url.deletingLastPathComponent()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != url.lastPathComponent else { return url }
        // Only the case changing is the same item, which the file system
        // may say already exists.
        let sameItem = trimmed.lowercased() == url.lastPathComponent.lowercased()
        let checked = sameItem ? trimmed : try Self.checkedName(name, defaultExtension: nil, in: folder)
        let renamed = folder.appendingPathComponent(checked).standardizedFileURL
        let moving = documents(inside: url)
        try FileManager.default.moveItem(at: url, to: renamed)
        let oldPath = url.standardizedFileURL.path
        for document in moving {
            guard let file = document.fileURL?.standardizedFileURL.path else { continue }
            document.fileURL = URL(fileURLWithPath: renamed.path + file.dropFirst(oldPath.count))
        }
        sidebarFolderChanged()
        if let currentDocument { show(currentDocument) }
        return renamed
    }

    /// Moves `url` to the Trash, closing the documents open here from it.
    func trash(_ url: URL) throws {
        try moveToTrash(url)
        for document in documents(inside: url) {
            forget(document)
        }
        sidebarFolderChanged()
    }

    // MARK: - Helpers

    /// The documents open in this window whose files are `url` or inside it.
    func documents(inside url: URL) -> [MarkdownDocument] {
        let path = url.standardizedFileURL.path
        return documents.filter { document in
            guard let file = document.fileURL?.standardizedFileURL.path else { return false }
            return file == path || file.hasPrefix(path.hasSuffix("/") ? path : path + "/")
        }
    }

    /// The item a sidebar menu item was chosen for.
    private func clickedURL(_ sender: Any?) -> URL? {
        (sender as? NSMenuItem)?.representedObject as? URL
    }

    /// Shows the outline's new state at once, rather than when the folder's
    /// watcher next reports, so the new item can be selected.
    private func sidebarFolderChanged() {
        sidebar.reload()
        filesChanged()
    }

    /// Runs `operation`, showing any error it throws.
    private func run(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            guard let window else { return }
            presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
        }
    }

    /// Asks for a name in a sheet, starting from `defaultName` with the part
    /// before any extension selected, and passes on the one given.
    private func askForName(title: String, defaultName: String, button: String = "Create",
                            then: @escaping (String) -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Name:"
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultName)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            then(field.stringValue)
        }
        let stem = (defaultName as NSString).deletingPathExtension
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
    }

    static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// The folder that new items go in for a click on `url`.
    static func folder(for url: URL) -> URL {
        isFolder(url) ? url : url.deletingLastPathComponent()
    }

    /// `base` with `extension`, or failing that the first of "base 2",
    /// "base 3"... not in `folder`.
    static func uniqueName(_ base: String, extension ext: String, in folder: URL) -> String {
        let name = { (number: Int) in
            let stem = number == 1 ? base : "\(base) \(number)"
            return ext.isEmpty ? stem : stem + "." + ext
        }
        var number = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name(number)).path) { number += 1 }
        return name(number)
    }

    /// `name` trimmed, with `defaultExtension` added if it has none, if it
    /// can name a new item in `folder`.
    static func checkedName(_ name: String, defaultExtension: String?, in folder: URL) throws -> String {
        var name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":"), !name.hasPrefix(".") else {
            throw NameError(message: "“\(name)” can't be used as a name.")
        }
        if let defaultExtension, (name as NSString).pathExtension.isEmpty { name += "." + defaultExtension }
        guard !FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) else {
            throw NameError(message: "“\(name)” is already in “\(folder.lastPathComponent)”.")
        }
        return name
    }

    struct NameError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
}
