import AppKit
import MarkupCore
import UniformTypeIdentifiers

/// The header's Insert Image button. The image can be anywhere. Its path is
/// written as short as it can be while still finding it (`imagePath(for:)`):
/// relative to the images directory, the document's folder, or that
/// folder's `resources` or `images` folder, or else in full.
extension EditorViewController {
    @objc func insertImage(_ sender: Any?) {
        guard !isShowingMarkdown, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose an image."
        panel.prompt = "Insert"
        panel.directoryURL = settings.imagesDirectory ?? document?.fileURL?.deletingLastPathComponent()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        let altField = NSTextField(string: "")
        altField.placeholderString = "Describes the image for people who can't see it"
        altField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        let accessory = NSStackView(views: [NSTextField(labelWithString: "Alt text:"), altField])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            insertImage(path: imagePath(for: url), alt: altField.stringValue)
        }
    }

    /// The path to write for the image at `url`: the shortest path relative
    /// to one of `imageFolders` that looking it up finds this same file (so
    /// just the name, for an image directly in one of them), or else the
    /// full path.
    func imagePath(for url: URL) -> String {
        let file = url.standardizedFileURL.resolvingSymlinksInPath().path
        let folders = imageFolders
        let paths = folders.compactMap { Self.path(of: url, relativeTo: $0) }.filter { path in
            MarkdownImage(alt: "", path: path).fileURL(in: folders)?.standardizedFileURL.resolvingSymlinksInPath().path == file
        }
        return paths.min { $0.split(separator: "/").count < $1.split(separator: "/").count } ?? file
    }

    /// Inserts the image at the selection, as if its Markdown had been typed.
    func insertImage(path: String, alt: String) {
        textView.insertText(MarkdownImage(alt: alt, path: path).markdown, replacementRange: textView.selectedRange())
    }

    /// The path of `file` from inside `folder`, or nil if it isn't inside.
    static func path(of file: URL, relativeTo folder: URL) -> String? {
        let filePath = file.standardizedFileURL.resolvingSymlinksInPath().path
        var folderPath = folder.standardizedFileURL.resolvingSymlinksInPath().path
        if !folderPath.hasSuffix("/") { folderPath += "/" }
        guard filePath.hasPrefix(folderPath), filePath.count > folderPath.count else { return nil }
        return String(filePath.dropFirst(folderPath.count))
    }
}
