import AppKit

/// A Markdown file. The Objective-C name matches `NSDocumentClass` in Info.plist.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    /// The Markdown read from disk. Once a window is open, the editor holds
    /// the live content and this is not kept up to date.
    private var markdown = ""

    // Classic Save / Save As behaviour rather than autosaving in place.
    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        let controller = EditorWindowController()
        addWindowController(controller)
        controller.load(markdown: markdown)
    }

    override func data(ofType typeName: String) throws -> Data {
        let editor = windowControllers.first as? EditorWindowController
        return Data((editor?.markdown ?? markdown).utf8)
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
}
