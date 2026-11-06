import AppKit
import MarkupCore

/// Links: the header's link button and Format > Link. A link is
/// `.markdownLink` on its text's characters, holding the destination, which
/// can be any reference, not only a URL. Saved as `[text](destination)`.
/// Clicking one follows it, and right-clicking one offers Open Link, Change
/// Link… and Remove Link.
extension EditorViewController {
    /// Asks for a link for the selection, or for the link the caret is in.
    /// With no selection and no link there, the link is inserted as its own
    /// text.
    @objc func editLink(_ sender: Any?) {
        guard !isShowingMarkdown, let window = view.window else { return }
        let range = linkTargetRange()
        let existing = range.length > 0 ? storage.attribute(.markdownLink, at: range.location, effectiveRange: nil) as? String
            : nil

        let alert = NSAlert()
        alert.messageText = existing == nil ? "Add Link" : "Edit Link"
        alert.informativeText = "A web address, a file, or any other reference."
        let field = NSTextField(string: existing ?? "")
        field.placeholderString = "https://example.com"
        field.widthAnchor.constraint(equalToConstant: 280).isActive = true
        let accessory = NSStackView(views: [NSTextField(labelWithString: "Link:"), field])
        accessory.frame = NSRect(x: 0, y: 0, width: 330, height: 24)
        alert.accessoryView = accessory
        alert.addButton(withTitle: existing == nil ? "Add Link" : "Change Link")
        alert.addButton(withTitle: "Cancel")
        if existing != nil {
            alert.addButton(withTitle: "Remove Link")
        }
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [self] response in
            switch response {
            case .alertFirstButtonReturn:
                setLink(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), in: range)
            case .alertThirdButtonReturn:
                setLink(nil, in: range)
            default:
                break
            }
            window.makeFirstResponder(textView)
        }
    }

    /// The range a link applies to: the selection, or with none, the whole
    /// link the caret is in (or the caret, if it isn't in one).
    func linkTargetRange() -> NSRange {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return selection }
        let contents = contentsRange(of: lineRange(at: selection.location))
        for location in [selection.location - 1, selection.location]
        where location >= contents.location && location < NSMaxRange(contents) {
            var run = NSRange()
            if storage.attribute(.markdownLink, at: location, longestEffectiveRange: &run, in: contents) != nil {
                return run
            }
        }
        return selection
    }

    /// Links `range` to `destination`, or unlinks it if that is nil or
    /// empty. An empty range gets the destination inserted as its text.
    /// Newlines, list markers and code blocks aren't linked.
    func setLink(_ destination: String?, in range: NSRange) {
        let destination = destination.flatMap { $0.isEmpty ? nil : $0 }
        var range = range
        if range.length == 0 {
            guard let destination else { return }
            textView.setSelectedRange(range)
            textView.insertText(destination, replacementRange: range)
            range.length = textView.selectedRange().location - range.location
            guard range.length > 0 else { return }
        }
        changeAttributes(in: range) {
            let string = storage.string as NSString
            for index in range.location..<NSMaxRange(range) {
                let character = NSRange(location: index, length: 1)
                if string.character(at: index) == 0x0A || storage.attribute(.listMarker, at: index, effectiveRange: nil) != nil
                    || storage.blockStyle(at: index) == .code {
                    storage.removeAttribute(.markdownLink, range: character)
                } else if let destination {
                    storage.addAttribute(.markdownLink, value: destination, range: character)
                } else {
                    storage.removeAttribute(.markdownLink, range: character)
                }
            }
            storage.applyInlineStyles(in: range)
        }
        undoManager?.setActionName(destination == nil ? "Remove Link" : "Link")
        updateForSelection()
    }

    /// The link that typing at the caret continues: one the caret is inside,
    /// not at either end of, so typing after a link doesn't extend it.
    /// Typing over a selection keeps the link of its first character.
    func linkForTyping() -> String? {
        let selection = textView.selectedRange()
        guard selection.location < storage.length else { return nil }
        let after = storage.attribute(.markdownLink, at: selection.location, effectiveRange: nil) as? String
        if selection.length > 0 { return after }
        guard selection.location > 0, let after,
              storage.attribute(.markdownLink, at: selection.location - 1, effectiveRange: nil) as? String == after
        else { return nil }
        return after
    }

    // MARK: - Following links

    /// Where a link goes.
    enum LinkTarget: Equatable {
        /// A heading, in this file (`file` nil) or another.
        case heading(file: URL?, id: String)
        /// A file, from this document's folder.
        case file(URL)
        /// A web address, or any other URL with a scheme.
        case url(URL)
    }

    /// Where `destination` goes, as `markBrokenLinks` reads it: `#id` to a
    /// heading here, or with `Settings.crossFileLinks` `idOnly`, the first
    /// file in the project with that ID; `path#id` to that file's heading.
    func linkTarget(for destination: String) -> LinkTarget? {
        let own = document?.fileURL?.standardizedFileURL
        if let reference = HeadingReference(destination: destination) {
            guard let path = reference.path else {
                if headingTitles[reference.id] != nil || currentHeadingTitles()[reference.id] != nil {
                    return .heading(file: nil, id: reference.id)
                }
                if settings.crossFileLinks == .idOnly,
                   let file = document?.project?.headingIDs().first(where: { $0.url != own && $0.ids.contains(reference.id) }) {
                    return .heading(file: file.url, id: reference.id)
                }
                return .heading(file: nil, id: reference.id)
            }
            guard let file = Self.file(at: path, from: document?.fileURL) else { return nil }
            return .heading(file: file == own ? nil : file, id: reference.id)
        }
        if let url = URL(string: destination), let scheme = url.scheme, scheme.count > 1 {
            return .url(url)
        }
        let path = destination.removingPercentEncoding ?? destination
        return Self.file(at: path, from: document?.fileURL).map { .file($0) }
    }

    /// Follows the link at character `index`: shows the heading it goes to,
    /// opening its file (in the project, if it's one of its files), or opens
    /// a web address in the browser, or a file in the app that opens it.
    func followLink(at index: Int) {
        guard !isShowingMarkdown, index < storage.length,
              let destination = storage.attribute(.markdownLink, at: index, effectiveRange: nil) as? String,
              let target = linkTarget(for: destination)
        else {
            NSSound.beep()
            return
        }
        switch target {
        case .heading(nil, let id):
            if !selectHeading(id: id) { NSSound.beep() }
        case .heading(let file?, let id):
            openInMarkup(file) { document in
                if !document.editor.selectHeading(id: id) { NSSound.beep() }
            }
        case .file(let file):
            if ProjectSidebarController.Node.isMarkdown(file), FileManager.default.fileExists(atPath: file.path) {
                openInMarkup(file) { _ in }
            } else {
                openExternally(file)
            }
        case .url(let url):
            openExternally(url)
        }
    }

    /// Opens the Markdown file `file`: in the project, if it's in its
    /// folder, or else in a window of its own.
    private func openInMarkup(_ file: URL, then: @escaping (MarkdownDocument) -> Void) {
        if let project = document?.project, file.path.hasPrefix(project.root.standardizedFileURL.path + "/") {
            project.open(file, then: then)
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { document, _, error in
            if let document = document as? MarkdownDocument {
                then(document)
            } else if let error {
                NSApp.presentError(error)
            }
        }
    }

    /// Puts the caret at the start of the heading with ID `id`, and shows
    /// it. Returns false if there's no such heading.
    @discardableResult
    func selectHeading(id: String) -> Bool {
        var found: NSRange?
        if isShowingMarkdown {
            // The heading's line, or the ID's line above it.
            let string = storage.string as NSString
            let range = string.range(of: "{#\(id)")
            if range.location != NSNotFound { found = NSRange(location: string.lineRange(for: range).location, length: 0) }
        } else {
            storage.enumerateAttribute(.headingAnchor, in: NSRange(location: 0, length: storage.length)) { value, run, stop in
                guard (value as? HeadingAnchor)?.id == id else { return }
                if let line = lineRanges(in: run).first(where: isTitledHeading) {
                    found = NSRange(location: contentsRange(of: line).location, length: 0)
                    stop.pointee = true
                }
            }
        }
        guard let found else { return false }
        textView.setSelectedRange(found)
        textView.scrollRangeToVisible(found)
        view.window?.makeFirstResponder(textView)
        let line = lineRange(at: found.location)
        textView.showFindIndicator(for: contentsRange(of: line))
        return true
    }

    // MARK: - The link menu

    /// Right-clicking a link adds Open Link, Change Link… and Remove Link to
    /// the top of the text view's menu, for that link.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        guard !isShowingMarkdown, let index = textView.linkIndex(at: textView.convert(event.locationInWindow, from: nil))
        else { return menu }
        let range = linkRange(at: index)
        let items = [
            NSMenuItem(title: "Open Link", action: #selector(openClickedLink(_:)), keyEquivalent: ""),
            NSMenuItem(title: "Change Link…", action: #selector(changeClickedLink(_:)), keyEquivalent: ""),
            NSMenuItem(title: "Remove Link", action: #selector(removeClickedLink(_:)), keyEquivalent: ""),
        ]
        for (offset, item) in items.enumerated() {
            item.target = self
            item.representedObject = NSValue(range: range)
            menu.insertItem(item, at: offset)
        }
        menu.insertItem(.separator(), at: items.count)
        return menu
    }

    /// The whole link that the character at `index` is in, on its line.
    func linkRange(at index: Int) -> NSRange {
        var run = NSRange()
        storage.attribute(.markdownLink, at: index, longestEffectiveRange: &run, in: contentsRange(of: lineRange(at: index)))
        return run
    }

    @objc func openClickedLink(_ sender: NSMenuItem) {
        guard let range = (sender.representedObject as? NSValue)?.rangeValue else { return }
        followLink(at: range.location)
    }

    @objc func changeClickedLink(_ sender: NSMenuItem) {
        guard let range = (sender.representedObject as? NSValue)?.rangeValue else { return }
        textView.setSelectedRange(range)
        editLink(sender)
    }

    @objc func removeClickedLink(_ sender: NSMenuItem) {
        guard let range = (sender.representedObject as? NSValue)?.rangeValue else { return }
        setLink(nil, in: range)
    }
}
