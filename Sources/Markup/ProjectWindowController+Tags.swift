import AppKit
import MarkupCore

/// Tags and citations (`MarkupTag`): values kept in the project folder's
/// `tags.txt` and `bibliography.txt` and written into its Markdown files,
/// along with bibliographies. Open documents follow changes to the files
/// (`EditorViewController.updateTags()`); Update Tags in Project rewrites
/// the others on disk.
extension ProjectWindowController {
    /// The values in the project's `tags.txt`, or nil if there is none.
    func tagValues() -> [String: String]? {
        if let read = tagValuesOnDisk { return read }
        let values = (try? String(contentsOf: root.appendingPathComponent(TagFile.name), encoding: .utf8))
            .map(TagFile.values(from:))
        tagValuesOnDisk = .some(values)
        return values
    }

    /// The project's `bibliography.txt`, or nil if there is none.
    func bibliography() -> Bibliography? {
        if let read = bibliographyOnDisk { return read }
        let bibliography = (try? String(contentsOf: root.appendingPathComponent(Bibliography.fileName), encoding: .utf8))
            .map(Bibliography.init(text:))
        bibliographyOnDisk = .some(bibliography)
        return bibliography
    }

    /// The project's tags and bibliography, written as `settings` says.
    func tagSources(settings: Settings) -> TagSources {
        TagSources(tags: tagValues(), bibliography: bibliography(), hangingBibliography: settings.hangingBibliography)
    }

    /// Insert > Update Tags in Project: sets the tags, citations and
    /// bibliographies in every Markdown file of the project, open documents
    /// as an edit, the others on disk.
    @objc func updateTagsInProject(_ sender: Any?) {
        let sources = tagSources(settings: .shared)
        guard !sources.isEmpty else { return }
        let (files, failed) = updateTags(from: sources)
        let alert = NSAlert()
        alert.messageText = files == 1 ? "Updated tags in 1 file." : "Updated tags in \(files) files."
        if !failed.isEmpty {
            alert.alertStyle = .warning
            alert.informativeText = "Couldn't save " + failed.map(\.lastPathComponent).joined(separator: ", ") + "."
        }
        alert.beginSheetModal(for: window!)
    }

    /// Sets the tags in the project's files from `sources`, returning how
    /// many files changed and those that couldn't be saved.
    func updateTags(from sources: TagSources) -> (files: Int, failed: [URL]) {
        var files = 0
        var failed: [URL] = []
        for file in markdownFiles() {
            if let document = documents.first(where: { $0.fileURL?.standardizedFileURL == file.url }) {
                if document.editorIfLoaded?.updateTags(from: sources) == true { files += 1 }
                continue
            }
            let updated = MarkupTag.updating(markdown: file.markdown, from: sources)
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
        menuItem.action == #selector(updateTagsInProject(_:)) ? !tagSources(settings: .shared).isEmpty : true
    }
}
