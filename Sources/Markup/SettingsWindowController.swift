import AppKit

/// Markup > Settings.
@MainActor
final class SettingsWindowController: NSWindowController {
    let settings: Settings
    let imagesDirectoryControl = NSPathControl()
    let clearButton = NSButton(title: "Clear", target: nil, action: nil)

    init(settings: Settings) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        super.init(window: window)

        let label = NSTextField(labelWithString: "Images directory:")
        imagesDirectoryControl.pathStyle = .standard
        imagesDirectoryControl.placeholderString = "None"
        imagesDirectoryControl.isEditable = false
        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseImagesDirectory(_:)))
        clearButton.target = self
        clearButton.action = #selector(clearImagesDirectory(_:))
        let note = NSTextField(wrappingLabelWithString:
            "Markup looks for a document's images in this folder, then in the document's own folder, "
                + "then in its resources and images folders.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let buttons = NSStackView(views: [chooseButton, clearButton])
        let grid = NSGridView(views: [
            [label, imagesDirectoryControl],
            [NSGridCell.emptyContentView, buttons],
            [NSGridCell.emptyContentView, note],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            imagesDirectoryControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 340),
        ])
        window.contentView = contentView
        showImagesDirectory()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc func chooseImagesDirectory(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = settings.imagesDirectory
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.setImagesDirectory(url)
        }
    }

    @objc func clearImagesDirectory(_ sender: Any?) {
        setImagesDirectory(nil)
    }

    func setImagesDirectory(_ url: URL?) {
        settings.imagesDirectory = url
        showImagesDirectory()
    }

    private func showImagesDirectory() {
        imagesDirectoryControl.url = settings.imagesDirectory
        clearButton.isEnabled = settings.imagesDirectory != nil
    }
}
