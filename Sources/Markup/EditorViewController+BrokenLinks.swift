import AppKit
import MarkupCore

/// A link to a heading, found in this file or another in the project.
struct HeadingLinkPlace: Equatable {
    /// The link's file, or nil for the document being edited.
    var file: URL?
    /// Which of the file's links to headings it is, counting from 0.
    var number: Int
    /// The link's text, without Markdown.
    var text: String
}

/// Links to headings that aren't there. After every change, links whose
/// heading ID can't be found (`#id`, or `other.md#id`) are highlighted in
/// red, and deleting a heading that links go to shows a bar saying
/// so, with Undo and Show Links, until the next edit.
extension EditorViewController {
    /// Checks the links once the current change is over, so a change made
    /// of several edits is checked once. `afterEdit` is true when the text
    /// changed, rather than other files.
    func scheduleLinkCheck(afterEdit: Bool = true) {
        linkCheckAfterEdit = linkCheckAfterEdit || afterEdit
        guard !isLinkCheckScheduled else { return }
        isLinkCheckScheduled = true
        Task { @MainActor [weak self] in
            guard let self, isLinkCheckScheduled else { return }
            checkLinks()
        }
    }

    /// Marks the links that go to no heading and, after an edit that
    /// removed headings with links to them, shows the deleted heading bar.
    func checkLinks() {
        let afterEdit = linkCheckAfterEdit
        isLinkCheckScheduled = false
        linkCheckAfterEdit = false
        guard !isShowingMarkdown, !isPlainText else { return }
        let titles = currentHeadingTitles()
        if afterEdit {
            let removed = headingTitles.keys.filter { titles[$0] == nil }.sorted()
            let places = removed.flatMap(linkPlaces(to:))
            if places.isEmpty {
                hideDeletedHeadingBar()
            } else {
                showDeletedHeadingBar(titles: removed.map { headingTitles[$0]! }, places: places)
            }
        }
        headingTitles = titles
        markBrokenLinks()
    }

    /// Starts afresh with the text just loaded: its headings are where
    /// deleting begins, and the bar goes.
    func resetLinkCheck() {
        headingTitles = currentHeadingTitles()
        hideDeletedHeadingBar()
        markBrokenLinks()
    }

    /// The IDs of the document's headings, and each heading's text.
    func currentHeadingTitles() -> [String: String] {
        var titles: [String: String] = [:]
        storage.enumerateAttribute(.headingAnchor, in: NSRange(location: 0, length: storage.length)) { value, run, _ in
            guard let anchor = value as? HeadingAnchor else { return }
            for line in lineRanges(in: run) where isTitledHeading(line) {
                titles[anchor.id] = (storage.string as NSString).substring(with: contentsRange(of: line))
                    .replacingOccurrences(of: "\u{FFFC}", with: "")
            }
        }
        return titles
    }

    // MARK: - Broken links

    /// Highlights the links to missing headings in red, without changing
    /// the text: the highlight is a temporary attribute, as
    /// spelling marks are.
    func markBrokenLinks() {
        guard let layoutManager = textView.layoutManager else { return }
        let all = NSRange(location: 0, length: storage.length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        brokenLinks = []
        guard !isShowingMarkdown, !isPlainText else { return }
        let ids = Set(headingTitles.keys)
        // Other files' IDs, found once, when first needed.
        var projectIDs: [(url: URL, ids: Set<String>)]?
        storage.enumerateAttribute(.markdownLink, in: all) { value, run, _ in
            guard let destination = value as? String, let reference = HeadingReference(destination: destination),
                  !isFound(reference, ownIDs: ids, projectIDs: {
                      if projectIDs == nil { projectIDs = document?.project?.headingIDs() ?? [] }
                      return projectIDs!
                  }) else { return }
            brokenLinks.append(run)
            layoutManager.addTemporaryAttribute(.backgroundColor, value: InlineStyle.brokenLinkColor, forCharacterRange: run)
        }
    }

    /// Whether `reference`, in this document, goes to a heading: one of
    /// `ownIDs` for `#id`, or as `Settings.crossFileLinks` has it, one
    /// anywhere in the project; for `other.md#id`, one in that file.
    private func isFound(_ reference: HeadingReference, ownIDs: Set<String>,
                         projectIDs: () -> [(url: URL, ids: Set<String>)]) -> Bool {
        guard let path = reference.path else {
            if ownIDs.contains(reference.id) { return true }
            guard settings.crossFileLinks == .idOnly else { return false }
            return projectIDs().contains { $0.ids.contains(reference.id) }
        }
        guard let file = Self.file(at: path, from: document?.fileURL) else { return false }
        if file == document?.fileURL?.standardizedFileURL { return ownIDs.contains(reference.id) }
        if let ids = projectIDs().first(where: { $0.url == file })?.ids {
            return ids.contains(reference.id)
        }
        guard let markdown = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return MarkdownCodec.headingIDs(inMarkdown: markdown).contains(reference.id)
    }

    /// The file a link's `path` names, from the folder of the file at
    /// `source`.
    static func file(at path: String, from source: URL?) -> URL? {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        guard let folder = source?.deletingLastPathComponent() else { return nil }
        return URL(fileURLWithPath: path, relativeTo: folder).standardizedFileURL
    }

    /// The tooltip of a broken link says why it is broken.
    func textView(_ textView: NSTextView, willDisplayToolTip tooltip: String, forCharacterAt characterIndex: Int) -> String? {
        guard brokenLinks.contains(where: { NSLocationInRange(characterIndex, $0) }) else { return tooltip }
        return "\(tooltip)\nNo heading has this ID."
    }

    // MARK: - Deleted headings

    /// The links to the heading with ID `id` in this file, the project's
    /// other files, or both.
    func linkPlaces(to id: String) -> [HeadingLinkPlace] {
        let own = document?.fileURL?.standardizedFileURL
        var places: [HeadingLinkPlace] = []
        for (number, link) in headingLinks().enumerated() {
            let reference = link.reference
            if reference.id == id, reference.path == nil || Self.file(at: reference.path!, from: own) == own {
                places.append(HeadingLinkPlace(file: nil, number: number, text: link.text))
            }
        }
        guard let own, let project = document?.project else { return places }
        for file in project.markdownFiles() where file.url != own {
            for (number, link) in HeadingReference.occurrences(inMarkdown: file.markdown).enumerated() {
                let reference = link.reference
                guard reference.id == id else { continue }
                let goesHere = reference.path.map { Self.file(at: $0, from: file.url) == own }
                    ?? (settings.crossFileLinks == .idOnly)
                if goesHere {
                    places.append(HeadingLinkPlace(file: file.url, number: number, text: link.text))
                }
            }
        }
        return places
    }

    /// The links to headings in the text, in order, with their ranges.
    func headingLinks() -> [(reference: HeadingReference, text: String, range: NSRange)] {
        var links: [(reference: HeadingReference, text: String, range: NSRange)] = []
        storage.enumerateAttribute(.markdownLink, in: NSRange(location: 0, length: storage.length)) { value, run, _ in
            guard let destination = value as? String, let reference = HeadingReference(destination: destination) else { return }
            links.append((reference, (storage.string as NSString).substring(with: run), run))
        }
        return links
    }

    /// Selects link `number` of the links to headings, and shows it.
    func selectHeadingLink(number: Int) {
        let links = headingLinks()
        guard links.indices.contains(number) else { return }
        let range = links[number].range
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
        view.window?.makeFirstResponder(textView)
    }

    func showDeletedHeadingBar(titles: [String], places: [HeadingLinkPlace]) {
        let links = places.count == 1 ? "1 link goes" : "\(places.count) links go"
        deletedHeadingBar.label.stringValue = titles.count == 1 ? "\(links) to “\(titles[0])”, which was deleted."
            : "\(links) to headings that were deleted."
        deletedHeadingBar.places = places
        deletedHeadingBar.isHidden = false
        deletedHeadingBarHeight.constant = DeletedHeadingBar.height
    }

    func hideDeletedHeadingBar() {
        deletedHeadingBar.places = []
        deletedHeadingBar.isHidden = true
        deletedHeadingBarHeight.constant = 0
    }

    @objc func undoHeadingDeletion(_ sender: Any?) {
        undoManager?.undo()
        view.window?.makeFirstResponder(textView)
    }

    /// Lists the links in a menu below the button; choosing one shows it,
    /// opening its file in the project if need be.
    @objc func showDeletedHeadingLinks(_ sender: NSButton) {
        let menu = NSMenu()
        for place in deletedHeadingBar.places {
            let file = place.file?.lastPathComponent ?? "This File"
            let item = NSMenuItem(title: "“\(place.text)” in \(file)", action: #selector(showHeadingLinkPlace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = place.file
            item.tag = place.number
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc func showHeadingLinkPlace(_ sender: NSMenuItem) {
        let number = sender.tag
        guard let file = sender.representedObject as? URL else {
            selectHeadingLink(number: number)
            return
        }
        document?.project?.open(file) { document in
            document.editor.selectHeadingLink(number: number)
        }
    }

    @objc func closeDeletedHeadingBar(_ sender: Any?) {
        hideDeletedHeadingBar()
    }
}

/// The bar below the header saying that links go to a deleted heading.
final class DeletedHeadingBar: NSView {
    static let height: CGFloat = 32

    let label = NSTextField(labelWithString: "")
    let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    let showLinksButton = NSButton(title: "Show Links", target: nil, action: nil)
    let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!,
                               target: nil, action: nil)
    /// The links that go to the deleted headings.
    var places: [HeadingLinkPlace] = []

    init(target: EditorViewController) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                              accessibilityDescription: "Warning")!)
        icon.contentTintColor = .systemYellow
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for (button, action) in [(undoButton, #selector(EditorViewController.undoHeadingDeletion(_:))),
                                 (showLinksButton, #selector(EditorViewController.showDeletedHeadingLinks(_:))),
                                 (closeButton, #selector(EditorViewController.closeDeletedHeadingBar(_:)))] {
            button.target = target
            button.action = action
            button.controlSize = .small
        }
        closeButton.isBordered = false
        closeButton.toolTip = "Close"

        let row = NSStackView(views: [icon, label, undoButton, showLinksButton])
        row.spacing = 8
        row.setCustomSpacing(12, after: label)
        row.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        addSubview(closeButton)
        addSubview(divider)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: topAnchor, constant: Self.height / 2),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor, constant: Self.height - 1),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemYellow.withAlphaComponent(0.15).setFill()
        dirtyRect.fill()
    }
}
