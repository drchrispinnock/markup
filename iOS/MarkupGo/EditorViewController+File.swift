import UIKit

extension EditorViewController {
    /// Shows the file's name and a Done button, and has the file save this
    /// editor's Markdown and reload it when it changes elsewhere.
    func connectFile() {
        guard let file else { return }
        navigationItem.title = file.localizedName
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.close()
            self?.dismiss(animated: true)
        })
        file.currentMarkdown = { [weak self] in
            MainActor.assumeIsolated { self?.markdown } ?? file.markdown
        }
        file.didReload = { [weak self] markdown in
            MainActor.assumeIsolated {
                guard let self, markdown != self.markdown else { return }
                let selection = self.textView.selectedRange
                self.load(markdown: markdown)
                self.textView.selectedRange = NSRange(location: min(selection.location, self.storage.length), length: 0)
            }
        }
    }

    /// Saves and closes the file.
    func close() {
        guard let file else { return }
        textView.resignFirstResponder()
        // The file saves after this editor has gone.
        let markdown = markdown
        file.currentMarkdown = { markdown }
        file.didReload = nil
        file.close { _ in }
    }
}
