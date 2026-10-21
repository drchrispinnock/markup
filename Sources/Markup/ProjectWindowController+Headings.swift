import AppKit
import MarkupCore

extension ProjectWindowController {
    /// Every Markdown file in the project's folder and its subfolders, with
    /// its Markdown: as edited for the documents open here, as on disk for
    /// the others. Hidden files and packages are skipped, as in the sidebar.
    func markdownFiles() -> [(url: URL, markdown: String)] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var files: [(url: URL, markdown: String)] = []
        for case let url as URL in enumerator where ProjectSidebarController.Node.isMarkdown(url) {
            let url = url.standardizedFileURL
            if let document = documents.first(where: { $0.fileURL?.standardizedFileURL == url }) {
                files.append((url, document.currentMarkdown))
            } else if let markdown = try? String(contentsOf: url, encoding: .utf8) {
                files.append((url, markdown))
            }
        }
        return files.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }
}
