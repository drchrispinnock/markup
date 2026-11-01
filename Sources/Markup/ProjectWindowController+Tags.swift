import AppKit
import MarkupCore

/// Variables and citations (`MarkupTag`): values kept in the project
/// folder's `variables.txt` (or `tags.txt`) and `bibliography.txt` and
/// written into its Markdown files, along with bibliographies. Open
/// documents follow changes to the files (`EditorViewController.updateTags()`);
/// Update Variables and Citations in Project rewrites the others on disk.
extension ProjectWindowController {
    /// The values in the project's `variables.txt` and `tags.txt`, or nil
    /// if there is neither.
    func variableValues() -> [String: String]? {
        if let read = variableValuesOnDisk { return read }
        let texts = VariableFile.names.compactMap { try? String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
        let values = texts.isEmpty ? nil : VariableFile.values(fromFiles: texts)
        variableValuesOnDisk = .some(values)
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

    /// Gives the entries of `bibliography.txt` cited by `keys` their keys,
    /// if they have none of their own (`Bibliography.pinningKeys`), so that
    /// editing their text doesn't lose the citations. Their keys don't
    /// change, so nor do the citations.
    func pinBibliographyKeys(_ keys: Set<String>) {
        let url = root.appendingPathComponent(Bibliography.fileName)
        guard !keys.isEmpty, let text = try? String(contentsOf: url, encoding: .utf8),
              let pinned = Bibliography.pinningKeys(keys, in: text) else { return }
        try? pinned.write(to: url, atomically: true, encoding: .utf8)
        bibliographyOnDisk = nil
    }

    /// The project's variables and bibliography, written as `settings` says.
    func tagSources(settings: Settings) -> TagSources {
        TagSources(variables: variableValues(), bibliography: bibliography(), hangingBibliography: settings.hangingBibliography)
    }

    /// How many of the project's Markdown files not open in an editor, which
    /// updates its own, have variables, citations or bibliographies out of
    /// date, as when `bibliography.txt` was edited in another app.
    func outOfDateFileCount(settings: Settings) -> Int {
        if let outOfDateFiles { return outOfDateFiles }
        let sources = tagSources(settings: settings)
        let count = sources.isEmpty ? 0 : markdownFiles().filter { file in
            !documents.contains { $0.fileURL?.standardizedFileURL == file.url }
                && MarkupTag.updating(markdown: file.markdown, from: sources) != file.markdown
        }.count
        outOfDateFiles = count
        return count
    }

    /// Insert > Update Variables and Citations in Project: sets the variables, citations and
    /// bibliographies in every Markdown file of the project, open documents
    /// as an edit, the others on disk.
    @objc func updateVariablesInProject(_ sender: Any?) {
        let sources = tagSources(settings: .shared)
        guard !sources.isEmpty else { return }
        let (files, failed) = updateTags(from: sources)
        let alert = NSAlert()
        alert.messageText = files == 1 ? "Updated 1 file." : "Updated \(files) files."
        if !failed.isEmpty {
            alert.alertStyle = .warning
            alert.informativeText = "Couldn't save " + failed.map(\.lastPathComponent).joined(separator: ", ") + "."
        }
        alert.beginSheetModal(for: window!)
    }

    /// Sets the variables and citations in the project's files from `sources`, returning how
    /// many files changed and those that couldn't be saved.
    func updateTags(from sources: TagSources) -> (files: Int, failed: [URL]) {
        var files = 0
        var failed: [URL] = []
        let markdownFiles = markdownFiles()
        pinBibliographyKeys(markdownFiles.reduce(into: Set()) { $0.formUnion(Bibliography.citedKeys(inMarkdown: $1.markdown)) })
        for file in markdownFiles {
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
        switch menuItem.action {
        case #selector(updateVariablesInProject(_:)):
            return !tagSources(settings: .shared).isEmpty
        case #selector(duplicateItem(_:)), #selector(renameItem(_:)), #selector(deleteItem(_:)):
            // Not the project folder itself.
            return (menuItem.representedObject as? URL).map { $0.standardizedFileURL != root } ?? false
        default:
            return true
        }
    }
}
