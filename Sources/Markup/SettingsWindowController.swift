import AppKit
import MarkupCore

/// Markup > Settings.
@MainActor
final class SettingsWindowController: NSWindowController {
    let settings: Settings
    let imagesDirectoryControl = NSPathControl()
    let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    let addsHeadingIDsCheckbox = NSButton(checkboxWithTitle: "Give headings an ID when saving", target: nil, action: nil)
    let headingIDFormPopUp = NSPopUpButton()
    let headingIDSchemePopUp = NSPopUpButton()
    let crossFileLinksPopUp = NSPopUpButton()
    let hangingBibliographyCheckbox = NSButton(checkboxWithTitle: "Use Leanpub's hanging paragraphs", target: nil,
                                               action: nil)
    let quickTagsCheckbox = NSButton(checkboxWithTitle: "Typing @name@ inserts the tag", target: nil, action: nil)

    static let formTitles: [HeadingAnchor.Form: String] = [
        .idLine: "{#id: x} above the heading",
        .braceLine: "{#x} above the heading",
        .attribute: "{#x} after the heading",
    ]

    static let crossFileLinkTitles: [Settings.CrossFileLinks: String] = [
        .idOnly: "#id (as Leanpub needs)",
        .withPath: "other.md#id",
        .off: "Only headings in the same file",
    ]

    static let schemeTitles: [HeadingIDScheme: String] = [
        .fileLevelWord: "File, level and first word (notes_2_Setting)",
        .hash: "8-character hash (3f9a1c0b)",
        .slug: "Heading in lower case (setting-up-my-dapp)",
    ]

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

        addsHeadingIDsCheckbox.target = self
        addsHeadingIDsCheckbox.action = #selector(headingIDsChanged(_:))
        for form in HeadingAnchor.Form.allCases {
            headingIDFormPopUp.addItem(withTitle: Self.formTitles[form]!)
            headingIDFormPopUp.lastItem?.representedObject = form.rawValue
        }
        for scheme in HeadingIDScheme.allCases {
            headingIDSchemePopUp.addItem(withTitle: Self.schemeTitles[scheme]!)
            headingIDSchemePopUp.lastItem?.representedObject = scheme.rawValue
        }
        for links in Settings.CrossFileLinks.allCases {
            crossFileLinksPopUp.addItem(withTitle: Self.crossFileLinkTitles[links]!)
            crossFileLinksPopUp.lastItem?.representedObject = links.rawValue
        }
        for popUp in [headingIDFormPopUp, headingIDSchemePopUp, crossFileLinksPopUp] {
            popUp.target = self
            popUp.action = #selector(headingIDsChanged(_:))
        }
        let idNote = NSTextField(wrappingLabelWithString:
            "Links to a heading use its ID, which is unique across the project. A cross link gives the heading "
                + "one if it has none. IDs already in a file are kept; edit them in the Markdown view.")
        idNote.textColor = .secondaryLabelColor
        idNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        quickTagsCheckbox.target = self
        quickTagsCheckbox.action = #selector(quickTagsChanged(_:))
        hangingBibliographyCheckbox.target = self
        hangingBibliographyCheckbox.action = #selector(quickTagsChanged(_:))
        let tagsNote = NSTextField(wrappingLabelWithString:
            "Tags show values from the project's tags.txt, and citations numbers from its bibliography.txt.")
        tagsNote.textColor = .secondaryLabelColor
        tagsNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let buttons = NSStackView(views: [chooseButton, clearButton])
        let grid = NSGridView(views: [
            [label, imagesDirectoryControl],
            [NSGridCell.emptyContentView, buttons],
            [NSGridCell.emptyContentView, note],
            [NSTextField(labelWithString: "Heading IDs:"), addsHeadingIDsCheckbox],
            [NSTextField(labelWithString: "Write as:"), headingIDFormPopUp],
            [NSTextField(labelWithString: "Make from:"), headingIDSchemePopUp],
            [NSGridCell.emptyContentView, idNote],
            [NSTextField(labelWithString: "Links to other files:"), crossFileLinksPopUp],
            [NSTextField(labelWithString: "Quick tags:"), quickTagsCheckbox],
            [NSTextField(labelWithString: "Bibliography:"), hangingBibliographyCheckbox],
            [NSGridCell.emptyContentView, tagsNote],
        ])
        grid.row(at: 3).topPadding = 12
        grid.row(at: 8).topPadding = 12
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
        showHeadingIDs()
        quickTagsCheckbox.state = settings.quickTags ? .on : .off
        hangingBibliographyCheckbox.state = settings.hangingBibliography ? .on : .off
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

    @objc func headingIDsChanged(_ sender: Any?) {
        settings.addsHeadingIDs = addsHeadingIDsCheckbox.state == .on
        if let form = (headingIDFormPopUp.selectedItem?.representedObject as? String).flatMap(HeadingAnchor.Form.init) {
            settings.headingIDForm = form
        }
        if let scheme = (headingIDSchemePopUp.selectedItem?.representedObject as? String).flatMap(HeadingIDScheme.init) {
            settings.headingIDScheme = scheme
        }
        if let links = (crossFileLinksPopUp.selectedItem?.representedObject as? String).flatMap(Settings.CrossFileLinks.init) {
            settings.crossFileLinks = links
        }
        showHeadingIDs()
    }

    @objc func quickTagsChanged(_ sender: Any?) {
        settings.quickTags = quickTagsCheckbox.state == .on
        settings.hangingBibliography = hangingBibliographyCheckbox.state == .on
    }

    private func showHeadingIDs() {
        addsHeadingIDsCheckbox.state = settings.addsHeadingIDs ? .on : .off
        headingIDFormPopUp.selectItem(at: HeadingAnchor.Form.allCases.firstIndex(of: settings.headingIDForm)!)
        headingIDSchemePopUp.selectItem(at: HeadingIDScheme.allCases.firstIndex(of: settings.headingIDScheme)!)
        crossFileLinksPopUp.selectItem(at: Settings.CrossFileLinks.allCases.firstIndex(of: settings.crossFileLinks)!)
    }

    private func showImagesDirectory() {
        imagesDirectoryControl.url = settings.imagesDirectory
        clearButton.isEnabled = settings.imagesDirectory != nil
    }
}
