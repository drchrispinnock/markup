import AppKit
import MarkupCore

extension Notification.Name {
    /// Posted by a project window when files in its folder change on disk.
    static let markupProjectFilesChanged = Notification.Name("MarkupProjectFilesChanged")
}

extension ProjectWindowController {
    /// Every Markdown file in the project's folder and its subfolders, with
    /// its Markdown: as edited for the documents open here, as on disk for
    /// the others. Hidden files and packages are skipped, as in the sidebar.
    /// The files on disk are read again once the folder changes.
    func markdownFiles() -> [(url: URL, markdown: String)] {
        let files = filesOnDisk ?? readFilesOnDisk()
        filesOnDisk = files
        return files.map { file in
            if let document = documents.first(where: { $0.fileURL?.standardizedFileURL == file.url }) {
                return (file.url, document.currentMarkdown)
            }
            return (file.url, file.markdown)
        }
    }

    /// The heading IDs in each of the project's Markdown files, as
    /// `markdownFiles()` has them, but without reading the files again.
    func headingIDs() -> [(url: URL, ids: Set<String>)] {
        let files = filesOnDisk ?? readFilesOnDisk()
        filesOnDisk = files
        return files.map { file in
            guard let document = documents.first(where: { $0.fileURL?.standardizedFileURL == file.url }) else {
                return (file.url, file.ids)
            }
            if let editor = document.editorIfLoaded, !editor.isShowingMarkdown {
                return (file.url, Set(editor.currentHeadingTitles().keys))
            }
            return (file.url, MarkdownCodec.headingIDs(inMarkdown: document.currentMarkdown))
        }
    }

    private func readFilesOnDisk() -> [(url: URL, markdown: String, ids: Set<String>)] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var files: [(url: URL, markdown: String, ids: Set<String>)] = []
        for case let url as URL in enumerator where ProjectSidebarController.Node.isMarkdown(url) {
            if let markdown = try? String(contentsOf: url, encoding: .utf8) {
                files.append((url.standardizedFileURL, markdown, MarkdownCodec.headingIDs(inMarkdown: markdown)))
            }
        }
        return files.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    /// Forgets the files read from disk, and tells the editors.
    func filesChanged() {
        filesOnDisk = nil
        variableValuesOnDisk = nil
        bibliographyOnDisk = nil
        outOfDateFiles = nil
        NotificationCenter.default.post(name: .markupProjectFilesChanged, object: self)
    }
}

extension ProjectWindowController {
    /// Insert > Fix Heading IDs for Leanpub: renames every heading ID in the
    /// project that Markua doesn't accept, and the links to it, and writes
    /// `{#id: x}` as `{id: x}`; open documents as an edit, the others on
    /// disk.
    @objc func fixHeadingIDsInProject(_ sender: Any?) {
        let renames = HeadingIDMigration.renames(for: headingIDs().reduce(into: Set()) { $0.formUnion($1.ids) })
        var files = 0
        var failed: [URL] = []
        for file in markdownFiles() {
            if let document = documents.first(where: { $0.fileURL?.standardizedFileURL == file.url }) {
                if document.editorIfLoaded?.migrateHeadingIDs(renames: renames) == true { files += 1 }
                continue
            }
            let migrated = HeadingIDMigration.migrating(markdown: file.markdown, renames: renames)
            guard migrated != file.markdown else { continue }
            do {
                try migrated.write(to: file.url, atomically: true, encoding: .utf8)
                files += 1
            } catch {
                failed.append(file.url)
            }
        }
        filesChanged()
        HeadingIDMigration.alert(renamed: renames.count, files: files, failed: failed).beginSheetModal(for: window!)
    }
}

extension HeadingIDMigration {
    /// What fixing the IDs did.
    @MainActor
    static func alert(renamed: Int, files: Int, failed: [URL]) -> NSAlert {
        let alert = NSAlert()
        if files == 0 && failed.isEmpty {
            alert.messageText = "The heading IDs are all ones Leanpub accepts."
        } else {
            let inFiles = files == 1 ? "1 file" : "\(files) files"
            alert.messageText = renamed == 0 ? "Updated \(inFiles)."
                : (renamed == 1 ? "Renamed 1 heading ID" : "Renamed \(renamed) heading IDs") + ", updating \(inFiles)."
            alert.informativeText = "IDs now start with a letter, links to them go to the new IDs, and {#id: x} is written {id: x}."
        }
        if !failed.isEmpty {
            alert.alertStyle = .warning
            alert.informativeText += (alert.informativeText.isEmpty ? "" : "\n\n") + "Couldn't save "
                + failed.map(\.lastPathComponent).joined(separator: ", ") + "."
        }
        return alert
    }
}
