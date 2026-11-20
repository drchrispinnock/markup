import UIKit

/// A Markdown file: its text as read, UTF-8 with CRLF made LF. The editor
/// showing it gives it fresh Markdown when it saves.
final class MarkdownFile: UIDocument {
    private(set) var markdown = ""
    /// Gives the Markdown to save, while an editor shows the file.
    var currentMarkdown: (() -> String)?
    /// Called when the file has been read again, changed elsewhere (by the
    /// Mac app over iCloud Drive, say).
    var didReload: ((String) -> Void)?

    override func contents(forType typeName: String) throws -> Any {
        if let currentMarkdown { markdown = currentMarkdown() }
        return Data(markdown.utf8)
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        markdown = text.replacingOccurrences(of: "\r\n", with: "\n")
        didReload?(markdown)
    }
}
