import AppKit
import MarkupCore

/// A Markdown file. The Objective-C name matches `NSDocumentClass` in Info.plist.
///
/// The document owns its editor, which is shown either in the document's own
/// window or in a project window. A project window shows one document at a
/// time; the others stay open, with their editors, unsaved changes and undo,
/// while the window shows another file.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    /// The Markdown read from disk. Once the editor exists, it holds the live
    /// content and this is not kept up to date.
    private var markdown = ""

    /// True for a file that isn't Markdown, which is edited as it is, with no
    /// formatting. Any plain text opens (see Info.plist), but only `.md` and
    /// `.markdown` files are Markdown. New documents are Markdown.
    private(set) var isPlainText = false

    nonisolated static let markdownExtensions: Set<String> = ["md", "markdown"]

    /// The project window this document is shown in, if any.
    weak var project: ProjectWindowController?

    // Classic Save / Save As behaviour rather than autosaving in place.
    override class var autosavesInPlace: Bool { false }

    private(set) var editorIfLoaded: EditorViewController?

    /// The document's editor, made with the Markdown read from disk.
    var editor: EditorViewController {
        if let editorIfLoaded { return editorIfLoaded }
        let editor = EditorViewController(plainText: isPlainText)
        editor.document = self
        editor.load(markdown: markdown)
        editorIfLoaded = editor
        return editor
    }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(editor: editor))
    }

    /// A document shown in a project window is shown there, not given a
    /// window of its own, as when File > Open picks it again.
    override func showWindows() {
        if windowControllers.isEmpty, let project {
            project.show(self)
        } else {
            super.showWindows()
        }
    }

    /// The document's Markdown, from the editor if there is one.
    var currentMarkdown: String {
        editorIfLoaded?.markdown ?? markdown
    }

    // Headings get their IDs before the save starts, so the document isn't
    // left edited by IDs added in the Markdown view.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        addMissingHeadingIDs(fileName: url.lastPathComponent)
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    /// Gives every heading without an ID a new one, as set in `Settings`,
    /// unlike any other ID in the project's files.
    func addMissingHeadingIDs(fileName: String?) {
        let settings = editorIfLoaded?.settings ?? .shared
        guard !isPlainText, settings.addsHeadingIDs else { return }
        editor.addMissingHeadingIDs(scheme: settings.headingIDScheme, form: settings.headingIDForm,
                                    fileName: fileName, taken: idsInOtherFiles())
    }

    /// The ID of the document's heading number `index` (counting from 0),
    /// given one first if it has none (as `settings` say, whether or not
    /// saving adds them), which leaves the document edited.
    func headingID(at index: Int, settings: Settings) -> String? {
        let headings = editor.headings
        guard headings.indices.contains(index) else { return nil }
        if let id = headings[index].anchor?.id { return id }
        editor.addMissingHeadingIDs(scheme: settings.headingIDScheme, form: settings.headingIDForm,
                                    fileName: fileURL?.lastPathComponent, taken: idsInOtherFiles(), onlyHeading: index)
        // In the Formatted view the ID is an attribute, which isn't an edit.
        if !editor.isShowingMarkdown { updateChangeCount(.changeDone) }
        return editor.headings[index].anchor?.id
    }

    /// The heading IDs in the project's other Markdown files.
    private func idsInOtherFiles() -> Set<String> {
        let own = fileURL?.standardizedFileURL
        return Set((project?.markdownFiles() ?? []).filter { $0.url != own }.flatMap { file in
            MarkdownCodec.lines(fromMarkdown: file.markdown).compactMap { $0.isHeading ? $0.anchor?.id : nil }
        })
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(currentMarkdown.utf8)
    }

    // Decided by the extension rather than the type, because another app's
    // type for .md files reaches here as plain text.
    override func read(from url: URL, ofType typeName: String) throws {
        let isPlainText = !Self.markdownExtensions.contains(url.pathExtension.lowercased())
        // On the main thread, as for read(from:ofType:) with data below.
        MainActor.assumeIsolated {
            self.isPlainText = isPlainText
        }
        try super.read(from: url, ofType: typeName)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        // Reads happen on the main thread unless canConcurrentlyReadDocuments
        // is overridden to return true.
        MainActor.assumeIsolated {
            markdown = text.replacingOccurrences(of: "\r\n", with: "\n")
        }
    }

    // Project windows mark the files with unsaved changes.
    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        NotificationCenter.default.post(name: .markdownDocumentEditedChanged, object: self)
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        NotificationCenter.default.post(name: .markdownDocumentEditedChanged, object: self)
    }
}

extension Notification.Name {
    /// Posted by a `MarkdownDocument` when it may have gained or lost unsaved
    /// changes, or been saved under a new name.
    static let markdownDocumentEditedChanged = Notification.Name("MarkupDocumentEditedChanged")
}
