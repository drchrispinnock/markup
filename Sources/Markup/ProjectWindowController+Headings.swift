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
        tagValuesOnDisk = nil
        bibliographyOnDisk = nil
        NotificationCenter.default.post(name: .markupProjectFilesChanged, object: self)
    }
}
