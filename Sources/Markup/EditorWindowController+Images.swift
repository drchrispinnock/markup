import AppKit
import MarkupCore
import UniformTypeIdentifiers

/// The header's Insert Image button. Images come from the images directory
/// (Markup > Settings), and are written as `![alt](path)` with the path
/// relative to that directory.
extension EditorWindowController {
    @objc func insertImage(_ sender: Any?) {
        guard !isShowingMarkdown, let window else { return }
        guard let folder = settings.imagesDirectory else {
            askForImagesDirectory(in: window)
            return
        }

        let panel = NSOpenPanel()
        panel.message = "Choose an image from your images directory."
        panel.prompt = "Insert"
        panel.directoryURL = folder
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let panelDelegate = ImagePanelDelegate(folder: folder)
        panel.delegate = panelDelegate

        let altField = NSTextField(string: "")
        altField.placeholderString = "Describes the image for people who can't see it"
        altField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        let accessory = NSStackView(views: [NSTextField(labelWithString: "Alt text:"), altField])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true

        panel.beginSheetModal(for: window) { [self] response in
            withExtendedLifetime(panelDelegate) {}
            guard response == .OK, let url = panel.url, let path = Self.path(of: url, relativeTo: folder) else { return }
            insertImage(path: path, alt: altField.stringValue)
        }
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

    private func askForImagesDirectory(in window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "No images directory"
        alert.informativeText = "Images are inserted from your images directory. Choose one in Settings."
        alert.addButton(withTitle: "Open Settings…")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
            }
        }
    }
}

/// Lets the open panel choose only files inside the images directory.
private final class ImagePanelDelegate: NSObject, NSOpenSavePanelDelegate {
    let folder: URL

    init(folder: URL) {
        self.folder = folder
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        EditorWindowController.path(of: url, relativeTo: folder) != nil
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard EditorWindowController.path(of: url, relativeTo: folder) != nil else {
            throw CocoaError(.fileReadNoPermission, userInfo: [
                NSLocalizedDescriptionKey: "Choose an image inside your images directory.",
            ])
        }
    }
}
