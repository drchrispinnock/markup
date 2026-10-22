import AppKit
import MarkupCore

/// Tags (`MarkupTag`): values kept in the project folder's `tags.txt` and
/// written into its Markdown files. Open documents follow changes to the
/// file (`EditorViewController.updateTags()`); Update Tags in Project
/// rewrites the others on disk.
extension ProjectWindowController {
    /// The values in the project's `tags.txt`, or nil if there is none.
    func tagValues() -> [String: String]? {
        if let read = tagValuesOnDisk { return read }
        let url = root.appendingPathComponent(TagFile.name)
        let values = (try? String(contentsOf: url, encoding: .utf8)).map(TagFile.values(from:))
        tagValuesOnDisk = .some(values)
        return values
    }

    /// Insert > Update Tags in Project: sets the tags in every Markdown file
    /// of the project from `tags.txt`, open documents as an edit, the others
    /// on disk.
    @objc func updateTagsInProject(_ sender: Any?) {
        guard let values = tagValues() else { return }
        let (files, failed) = updateTags(from: values)
        let alert = NSAlert()
        alert.messageText = files == 1 ? "Updated tags in 1 file." : "Updated tags in \(files) files."
        if !failed.isEmpty {
            alert.alertStyle = .warning
            alert.informativeText = "Couldn't save " + failed.map(\.lastPathComponent).joined(separator: ", ") + "."
        }
        alert.beginSheetModal(for: window!)
    }

    /// Sets the tags in the project's files from `values`, returning how
    /// many files changed and those that couldn't be saved.
    func updateTags(from values: [String: String]) -> (files: Int, failed: [URL]) {
        var files = 0
        var failed: [URL] = []
        for file in markdownFiles() {
            if let document = documents.first(where: { $0.fileURL?.standardizedFileURL == file.url }) {
                if document.editorIfLoaded?.updateTags(from: values) == true { files += 1 }
                continue
            }
            let updated = MarkupTag.updating(markdown: file.markdown, from: values)
            guard updated != file.markdown else { continue }
            do {
                try updated.write(to: file.url, atomically: true, encoding: .utf8)
                files += 1
            } catch {
                failed.append(file.url)
            }
        }
        filesChanged()
        return (files, failed)
    }
}

extension ProjectWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(updateTagsInProject(_:)) ? tagValues() != nil : true
    }
}
