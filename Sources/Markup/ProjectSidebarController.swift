import AppKit
import UniformTypeIdentifiers

/// A project window's sidebar: the project folder at the top, and inside it
/// its subfolders and Markdown and other plain text files, as an outline
/// whose folders open and close. Hidden files and packages are left out. It
/// follows changes on disk, keeping folders open and the selection where
/// they were.
@MainActor
final class ProjectSidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    /// A file or folder in the outline. Folders read their contents when
    /// first asked.
    final class Node {
        let url: URL
        let isFolder: Bool
        private var loadedChildren: [Node]?

        init(url: URL, isFolder: Bool) {
            self.url = url
            self.isFolder = isFolder
        }

        var name: String { url.lastPathComponent }

        var children: [Node] {
            if let loadedChildren { return loadedChildren }
            let children = isFolder ? Self.contents(of: url) : []
            loadedChildren = children
            return children
        }

        /// Folders first, then files, each in Finder's order.
        private static func contents(of folder: URL) -> [Node] {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentTypeKey]
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                     options: [.skipsHiddenFiles])) ?? []
            let nodes = urls.compactMap { url -> Node? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true {
                    return values?.isPackage == true ? nil : Node(url: url.standardizedFileURL, isFolder: true)
                }
                let isText = isMarkdown(url) || values?.contentType?.conforms(to: .plainText) == true
                return isText ? Node(url: url.standardizedFileURL, isFolder: false) : nil
            }
            return nodes.sorted { a, b in
                a.isFolder != b.isFolder ? a.isFolder : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }

        static func isMarkdown(_ url: URL) -> Bool {
            ["md", "markdown"].contains(url.pathExtension.lowercased())
        }
    }

    let root: URL
    let outlineView = NSOutlineView()
    private(set) var rootNode: Node
    private var watcher: DirectoryWatcher?
    /// Files with unsaved changes, marked with a dot.
    private var editedFiles: Set<URL> = []
    /// True while the outline's selection is being set to match the window,
    /// so it isn't taken as the user choosing a file.
    private var isSelecting = false

    /// Called when the user chooses a file.
    var onChoose: ((URL) -> Void)?
    /// Called when anything in the folder changes.
    var onFolderChange: (() -> Void)?
    /// Where the menu's items are sent: the project window.
    weak var menuTarget: AnyObject?

    init(root: URL) {
        self.root = root
        rootNode = Node(url: root, isFolder: true)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .default
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.autosaveExpandedItems = false
        outlineView.menu = makeMenu()
        // The project folder starts open.
        outlineView.reloadData()
        outlineView.expandItem(rootNode)

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        view = scrollView

        watcher = DirectoryWatcher(url: root) { [weak self] in
            self?.reload()
            self?.onFolderChange?()
        }
    }

    /// The menu for a right click: New File, New Folder, Duplicate, Rename
    /// and Delete, sent to `menuTarget` (`ProjectWindowController+Files`), each
    /// carrying the item clicked.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "New File…", action: #selector(ProjectWindowController.newFile(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "New Folder…", action: #selector(ProjectWindowController.newFolder(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Duplicate", action: #selector(ProjectWindowController.duplicateItem(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Rename…", action: #selector(ProjectWindowController.renameItem(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Delete", action: #selector(ProjectWindowController.deleteItem(_:)), keyEquivalent: "")
        return menu
    }

    /// The item right-clicked, or the project folder for a click below the
    /// rows.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let clicked = (outlineView.item(atRow: outlineView.clickedRow) as? Node)?.url ?? root
        for item in menu.items {
            item.target = menuTarget
            item.representedObject = clicked
        }
    }

    func stopWatching() {
        watcher = nil
    }

    /// Reads the folder again, keeping the open folders and the selection.
    func reload() {
        let expanded = (0..<outlineView.numberOfRows).compactMap { row -> URL? in
            guard let node = outlineView.item(atRow: row) as? Node, outlineView.isItemExpanded(node) else { return nil }
            return node.url
        }
        let selected = (outlineView.item(atRow: outlineView.selectedRow) as? Node)?.url
        let rootWasExpanded = outlineView.isItemExpanded(rootNode)
        rootNode = Node(url: root, isFolder: true)
        isSelecting = true
        outlineView.reloadData()
        if rootWasExpanded { outlineView.expandItem(rootNode) }
        for url in expanded {
            if let node = node(for: url) { outlineView.expandItem(node) }
        }
        isSelecting = false
        select(selected)
    }

    /// Selects the file at `url`, opening the folders it's in, or clears the
    /// selection if it isn't in the outline.
    func select(_ url: URL?) {
        isSelecting = true
        defer { isSelecting = false }
        guard let url, let node = node(for: url.standardizedFileURL) else {
            outlineView.deselectAll(nil)
            return
        }
        // The folders on the way to it, from the top, opening each so the
        // outline knows the next. It knows only the items of open folders.
        var folder = url.standardizedFileURL.deletingLastPathComponent()
        var ancestors: [Node] = []
        while let ancestor = self.node(for: folder) {
            ancestors.insert(ancestor, at: 0)
            guard ancestor !== rootNode else { break }
            folder = folder.deletingLastPathComponent()
        }
        ancestors.forEach { outlineView.expandItem($0) }
        let row = outlineView.row(forItem: node)
        if row >= 0 {
            outlineView.selectRowIndexes([row], byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        }
    }

    func reloadEditedMarks(edited: Set<URL>) {
        editedFiles = Set(edited.map(\.standardizedFileURL))
        outlineView.reloadData(forRowIndexes: IndexSet(0..<outlineView.numberOfRows), columnIndexes: [0])
    }

    /// The node for `url`, the project folder or something in it, reading
    /// the folders on the way to it.
    func node(for url: URL) -> Node? {
        let rootComponents = root.pathComponents
        let components = url.pathComponents
        guard components.count >= rootComponents.count, Array(components.prefix(rootComponents.count)) == rootComponents
        else { return nil }
        var node = rootNode
        for name in components.dropFirst(rootComponents.count) {
            guard let child = node.children.first(where: { $0.name == name }) else { return nil }
            node = child
        }
        return node
    }

    // MARK: - NSOutlineViewDataSource

    // The outline's one top item is the project folder.

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Node)?.children.count ?? 1
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Node)?.children[index] ?? rootNode
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.isFolder ?? false
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("file")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? FileCell ?? FileCell()
        cell.identifier = identifier
        cell.textField?.stringValue = node.name
        // The project folder's name stands out.
        cell.textField?.font = node === rootNode ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
        let symbol = node.isFolder ? "folder" : Node.isMarkdown(node.url) ? "doc.richtext" : "doc.plaintext"
        cell.imageView?.image = NSImage(systemSymbolName: symbol,
                                        accessibilityDescription: nil)
        cell.editedMark.isHidden = !editedFiles.contains(node.url)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isSelecting, let node = outlineView.item(atRow: outlineView.selectedRow) as? Node, !node.isFolder
        else { return }
        onChoose?(node.url)
    }

    /// A row: icon, name, and a dot if the file has unsaved changes.
    final class FileCell: NSTableCellView {
        let editedMark = NSImageView(image: NSImage(systemSymbolName: "circle.fill",
                                                    accessibilityDescription: "Unsaved changes")!)

        init() {
            super.init(frame: .zero)
            let icon = NSImageView()
            let name = NSTextField(labelWithString: "")
            name.lineBreakMode = .byTruncatingMiddle
            editedMark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 6, weight: .regular)
            editedMark.contentTintColor = .secondaryLabelColor
            for view in [icon, name, editedMark] {
                view.translatesAutoresizingMaskIntoConstraints = false
                addSubview(view)
            }
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            imageView = icon
            textField = name
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                name.centerYAnchor.constraint(equalTo: centerYAnchor),
                editedMark.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 4),
                editedMark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                editedMark.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }
    }
}
