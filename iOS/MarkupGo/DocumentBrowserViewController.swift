import UIKit
import UniformTypeIdentifiers

extension UTType {
    /// Markdown, declared (imported) in Info.plist.
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// The app's root: the system's file browser, showing Markdown files in
/// iCloud Drive, On My iPhone and other providers. Picking or creating one
/// opens it in an editor.
final class DocumentBrowserViewController: UIDocumentBrowserViewController,
    @preconcurrency UIDocumentBrowserViewControllerDelegate {
    init() {
        super.init(forOpening: [.markdownText])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        allowsDocumentCreation = true
        allowsPickingMultipleItems = false
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController,
                         didRequestDocumentCreationWithHandler importHandler: @escaping (URL?, ImportMode) -> Void) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Untitled.md")
        do {
            try Data().write(to: url)
            importHandler(url, .move)
        } catch {
            importHandler(nil, .none)
        }
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController, didPickDocumentsAt documentURLs: [URL]) {
        if let url = documentURLs.first { open(url) }
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController, didImportDocumentAt sourceURL: URL,
                         toDestinationURL destinationURL: URL) {
        open(destinationURL)
    }

    func documentBrowser(_ controller: UIDocumentBrowserViewController, failedToImportDocumentAt documentURL: URL,
                         error: Error?) {
        showError("The file couldn’t be created.", error)
    }

    /// Opens the file at `url` in an editor, over the browser.
    func open(_ url: URL) {
        // Already showing it.
        if let editor = (presentedViewController as? UINavigationController)?.viewControllers.first as? EditorViewController,
           editor.file?.fileURL == url {
            return
        }
        // UIDocument isn't Sendable, but opens on the main queue.
        nonisolated(unsafe) let file = MarkdownFile(fileURL: url)
        Task {
            guard await file.open() else {
                showError("“\(url.lastPathComponent)” couldn’t be opened.", nil)
                return
            }
            if let presented = presentedViewController {
                ((presented as? UINavigationController)?.viewControllers.first as? EditorViewController)?.close()
                await withCheckedContinuation { done in dismiss(animated: false) { done.resume() } }
            }
            let navigation = UINavigationController(rootViewController: EditorViewController(file: file, markdown: file.markdown))
            navigation.modalPresentationStyle = .fullScreen
            present(navigation, animated: true)
        }
    }

    private func showError(_ message: String, _ error: Error?) {
        let alert = UIAlertController(title: message, message: error?.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
