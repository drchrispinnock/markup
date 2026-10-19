import AppKit

/// A window for a folder (File > Open Project): a sidebar listing the folder's
/// Markdown files, and the editor of the one chosen.
///
/// Each file chosen is opened as a `MarkdownDocument` without a window of its
/// own, and stays open while the window shows other files, keeping its
/// unsaved changes and undo. The window controller isn't any document's
/// window controller; it passes document actions (Save, Print...) to the
/// document shown, and asks about each file's unsaved changes when closed.
@MainActor
final class ProjectWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let root: URL
    let sidebar: ProjectSidebarController
    private let splitViewController = NSSplitViewController()
    private let editorContainer = NSViewController()
    private let placeholder = NSTextField(labelWithString: "Choose a file in the sidebar.")

    /// The documents opened in this window, in the order they were opened.
    private(set) var documents: [MarkdownDocument] = []
    /// The document shown.
    private(set) var currentDocument: MarkdownDocument?

    /// Documents still to ask about while closing.
    private var documentsToReview: [MarkdownDocument] = []

    /// Called once the window has closed.
    var onClose: (() -> Void)?

    init(root: URL) {
        self.root = root.standardizedFileURL
        sidebar = ProjectSidebarController(root: self.root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        editorContainer.view = NSView()
        placeholder.textColor = .secondaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: editorContainer.view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: editorContainer.view.centerYAnchor),
        ])

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 400
        splitViewController.addSplitViewItem(sidebarItem)
        let editorItem = NSSplitViewItem(viewController: editorContainer)
        editorItem.minimumThickness = 400
        splitViewController.addSplitViewItem(editorItem)
        splitViewController.splitView.autosaveName = "MarkupProjectSplit"

        window.contentViewController = splitViewController
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.minSize = NSSize(width: 640, height: 360)
        window.center()
        window.setFrameAutosaveName("MarkupProject \(self.root.path)")
        window.delegate = self

        // The sidebar's show / hide button, in the title bar.
        let toolbar = NSToolbar(identifier: "MarkupProject")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact

        sidebar.onChoose = { [unowned self] url in open(url) }
        updateTitle()

        NotificationCenter.default.addObserver(self, selector: #selector(documentEditedChanged(_:)),
                                               name: .markdownDocumentEditedChanged, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Showing files

    /// Opens the Markdown file at `url` and shows it. A file already open
    /// in a window of its own is brought to the front there instead.
    func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { [weak self] document, _, error in
            guard let self else { return }
            if let document = document as? MarkdownDocument {
                show(document)
            } else if let error {
                presentError(error, modalFor: window!, delegate: nil, didPresent: nil, contextInfo: nil)
            }
        }
    }

    /// Shows `document`'s editor in the window.
    func show(_ document: MarkdownDocument) {
        // A document has one editor, so one place to show it.
        if !document.windowControllers.isEmpty {
            document.showWindows()
            sidebar.select(currentDocument?.fileURL)
            return
        }
        if let other = document.project, other !== self {
            other.show(document)
            other.showWindow(nil)
            sidebar.select(currentDocument?.fileURL)
            return
        }
        document.project = self
        if !documents.contains(where: { $0 === document }) {
            documents.append(document)
        }

        if currentDocument !== document {
            currentDocument?.editorIfLoaded?.removeFromParent()
            currentDocument?.editorIfLoaded?.view.removeFromSuperview()
            currentDocument = document

            let editor = document.editor
            editorContainer.addChild(editor)
            editor.view.translatesAutoresizingMaskIntoConstraints = false
            editorContainer.view.addSubview(editor.view)
            NSLayoutConstraint.activate([
                editor.view.topAnchor.constraint(equalTo: editorContainer.view.safeAreaLayoutGuide.topAnchor),
                editor.view.leadingAnchor.constraint(equalTo: editorContainer.view.leadingAnchor),
                editor.view.trailingAnchor.constraint(equalTo: editorContainer.view.trailingAnchor),
                editor.view.bottomAnchor.constraint(equalTo: editorContainer.view.bottomAnchor),
            ])
            placeholder.isHidden = true
        }
        window?.makeFirstResponder(document.editor.textView)
        sidebar.select(document.fileURL)
        updateTitle()
    }

    private func updateTitle() {
        guard let window else { return }
        if let currentDocument {
            window.title = currentDocument.displayName
            window.subtitle = root.lastPathComponent
            window.representedURL = currentDocument.fileURL
            window.isDocumentEdited = currentDocument.isDocumentEdited
        } else {
            window.title = root.lastPathComponent
            window.subtitle = ""
            window.representedURL = root
            window.isDocumentEdited = false
        }
    }

    @objc private func documentEditedChanged(_ notification: Notification) {
        guard let document = notification.object as? MarkdownDocument,
              documents.contains(where: { $0 === document }) else { return }
        sidebar.reloadEditedMarks(edited: Set(documents.filter(\.isDocumentEdited).compactMap(\.fileURL)))
        if document === currentDocument {
            updateTitle()
            sidebar.select(document.fileURL)
        }
    }

    // MARK: - Responder chain

    /// Save, Save As, Print and the like go to the document shown.
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if let currentDocument, currentDocument.responds(to: action) {
            return currentDocument
        }
        return super.supplementalTarget(forAction: action, sender: sender)
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        currentDocument?.undoManager
    }

    /// Asks about each file with unsaved changes in turn, showing it, before
    /// the window closes.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        documentsToReview = documents.filter(\.isDocumentEdited)
        guard documentsToReview.isEmpty else {
            reviewNextDocument()
            return false
        }
        return true
    }

    private func reviewNextDocument() {
        guard !documentsToReview.isEmpty else {
            window?.close()
            return
        }
        let document = documentsToReview.removeFirst()
        show(document)
        document.canClose(withDelegate: self, shouldClose: #selector(document(_:shouldClose:contextInfo:)),
                          contextInfo: nil)
    }

    @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if shouldClose {
            reviewNextDocument()
        } else {
            documentsToReview = []
        }
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: .markdownDocumentEditedChanged, object: nil)
        for document in documents where document.project === self {
            document.project = nil
            if document.windowControllers.isEmpty {
                document.close()
            }
        }
        documents = []
        currentDocument = nil
        sidebar.stopWatching()
        onClose?()
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        NSToolbarItem(itemIdentifier: itemIdentifier)
    }
}
