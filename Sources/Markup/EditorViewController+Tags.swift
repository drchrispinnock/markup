import AppKit
import MarkupCore

/// Variables and citations (`MarkupTag`): each is one attachment character
/// showing its value (`TagAttachmentCell`), carrying `.markupTag`.
/// Variables' values come from the project's `variables.txt` (or
/// `tags.txt`), citations' (`[1]`) from its `bibliography.txt`, and
/// bibliographies (`Bibliography`) are written from that too. They follow
/// the files: when they change, and when the editor appears, `updateTags()`
/// sets every value and rewrites every bibliography, as an edit that can be
/// undone. A document outside a project keeps what it has.
///
/// Insert > Variable asks for a variable's name, offering those in
/// `variables.txt`. With the quick variables setting, `@name@` typed
/// becomes that variable. Insert > Citation offers the bibliography's
/// entries, and Insert > Bibliography writes the bibliography.
extension EditorViewController {
    /// The project's variables and bibliography, or nil outside a project.
    var tagSources: TagSources? {
        document?.project?.tagSources(settings: settings)
    }

    /// Sets every variable's and citation's value, and every bibliography,
    /// from the project's files.
    func updateTags() {
        guard let sources = tagSources, !sources.isEmpty else { return }
        updateTags(from: sources)
    }

    /// Sets every variable's and citation's value, and every bibliography,
    /// from `sources`, returning whether anything changed. The Markdown view's
    /// text is left alone: switching back updates it.
    @discardableResult
    func updateTags(from sources: TagSources) -> Bool {
        guard !isShowingMarkdown, !isPlainText else { return false }
        var changes: [(NSRange, MarkupTag)] = []
        storage.enumerateAttribute(.markupTag, in: NSRange(location: 0, length: storage.length)) { value, run, _ in
            guard let tag = value as? MarkupTag else { return }
            for index in run.location..<NSMaxRange(run) {
                let updated = tag.updated(from: sources)
                if updated != tag { changes.append((NSRange(location: index, length: 1), updated)) }
            }
        }
        if let first = changes.first, let last = changes.last {
            changeAttributes(in: NSUnionRange(first.0, last.0)) {
                for (range, tag) in changes {
                    storage.addAttributes([.markupTag: tag, .toolTip: tag.toolTip], range: range)
                }
            }
        }
        let rewrote = sources.bibliography.map { rewriteBibliographies($0, hanging: sources.hangingBibliography) } ?? false
        guard !changes.isEmpty || rewrote else { return false }
        undoManager?.setActionName("Update Variables")
        return true
    }

    // MARK: - Bibliographies

    /// The bibliographies in the text: each from the start of the line
    /// holding only its start marker to the end of the line holding only
    /// its end marker, newline excluded.
    func bibliographyRanges() -> [NSRange] {
        var ranges: [NSRange] = []
        var start: Int?
        storage.enumerateAttribute(.markdownComment, in: NSRange(location: 0, length: storage.length)) { value, run, _ in
            guard let comment = (value as? String)?.trimmingCharacters(in: .whitespaces) else { return }
            let line = lineRange(at: run.location)
            guard contentsRange(of: line) == run, listItem(at: line) == nil else { return }
            if comment == Bibliography.start {
                start = line.location
            } else if comment == Bibliography.end, let first = start {
                ranges.append(NSRange(location: first, length: NSMaxRange(run) - first))
                start = nil
            }
        }
        return ranges
    }

    /// Writes each bibliography in the text again from `bibliography`, if
    /// it has changed, returning whether any had.
    private func rewriteBibliographies(_ bibliography: Bibliography, hanging: Bool) -> Bool {
        let wanted = bibliography.markdown(hanging: hanging)
        var rewrote = false
        for range in bibliographyRanges().reversed() {
            let current = MarkdownCodec.markdown(from: markdownLines(from: range.location, to: NSMaxRange(range)))
            guard Bibliography.normalized(current) != Bibliography.normalized(wanted) else { continue }
            replaceCharacters(in: range, with: Self.formattedText(fromMarkdown: wanted, imageFolders: imageFolders))
            rewrote = true
        }
        return rewrote
    }

    /// Insert > Bibliography: writes the project's bibliography on lines of
    /// its own at the caret, or below its line.
    @objc func insertBibliography(_ sender: Any?) {
        guard !isShowingMarkdown, !isPlainText, let sources = tagSources, let bibliography = sources.bibliography else { return }
        var line = lineRange(at: textView.selectedRange().location)
        if isTableLine(line) { line = tableLines(around: line).last! }
        let text = NSMutableAttributedString(attributedString: Self.formattedText(
            fromMarkdown: bibliography.markdown(hanging: sources.hangingBibliography), imageFolders: imageFolders))
        let contents = contentsRange(of: line)
        let location: Int
        if contents.length == 0, !isTableLine(line) {
            location = line.location
        } else if NSMaxRange(contents) == NSMaxRange(line) {
            // The last line, with no newline to end it.
            location = NSMaxRange(line)
            text.insert(NSAttributedString(string: "\n", attributes: BlockStyle.paragraph.attributes), at: 0)
        } else {
            location = NSMaxRange(line)
            text.append(NSAttributedString(string: "\n", attributes: BlockStyle.paragraph.attributes))
        }
        replaceCharacters(in: NSRange(location: location, length: 0), with: text)
        textView.setSelectedRange(NSRange(location: location + text.length, length: 0))
        undoManager?.setActionName("Insert Bibliography")
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Citations

    /// Insert > Citation: offers the bibliography's entries in a popover at
    /// the caret, then cites the one chosen.
    @objc func insertCitation(_ sender: Any?) {
        guard !isShowingMarkdown, !isPlainText else { return }
        presentAtCaret(CitationController(bibliography: tagSources?.bibliography) { [weak self] key in
            self?.insertCitation(of: key)
        })
    }

    /// Cites the entry `key` at the selection, as if its Markdown had been
    /// typed.
    func insertCitation(of key: String) {
        guard MarkupTag.isValid(name: key) else { return }
        textView.insertText(MarkupTag.citation(key).updated(from: tagSources ?? TagSources()).markdown,
                            replacementRange: textView.selectedRange())
        undoManager?.setActionName("Insert Citation")
        view.window?.makeFirstResponder(textView)
    }

    /// Shows `controller` in a popover below the caret.
    private func presentAtCaret(_ controller: NSViewController) {
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let caret = textView.selectedRange()
        var rect = textView.firstRect(forCharacterRange: NSRange(location: caret.location, length: 0), actualRange: nil)
        rect = textView.convert(view.window?.convertFromScreen(rect) ?? rect, from: nil)
        rect.size.width = max(rect.width, 1)
        present(controller, asPopoverRelativeTo: rect, of: textView, preferredEdge: .maxY, behavior: .transient)
    }

    // MARK: - Inserting

    /// Insert > Variable: asks for the variable's name in a popover at the
    /// caret, then inserts the variable.
    @objc func insertVariable(_ sender: Any?) {
        guard !isShowingMarkdown, !isPlainText else { return }
        presentAtCaret(makeVariableController())
    }

    func makeVariableController() -> VariableController {
        VariableController(names: (tagSources?.variables ?? [:]).keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }) {
            [weak self] name in self?.insertVariable(named: name)
        }
    }

    /// Inserts the variable `name` at the selection, as if its Markdown had
    /// been typed.
    func insertVariable(named name: String) {
        guard MarkupTag.isValid(name: name) else { return }
        let variable = MarkupTag(name: name, value: MarkupTag.unknownValue).updated(from: tagSources ?? TagSources())
        textView.insertText(variable.markdown, replacementRange: textView.selectedRange())
        undoManager?.setActionName("Insert Variable")
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Typed variables and citations

    private static let quickVariable = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_.@\-])@([\p{L}\p{N}_.\-]+)@"#)

    /// Replaces typed or pasted variables and citations that the edit
    /// touched, and with the quick variables setting, `@name@`, with the
    /// variable. Its value is
    /// set from the project's files, if there are any.
    func convertTags(in line: NSRange, after edit: NSRange) {
        let contents = contentsRange(of: line)
        let string = storage.string as NSString
        let text = string.substring(with: contents)
        var found = MarkupTag.tags(in: text).map { (range: NSRange(location: $0.range.lowerBound, length: $0.range.count), tag: $0.tag) }
        if settings.quickVariables {
            for match in Self.quickVariable.matches(in: text, range: NSRange(location: 0, length: contents.length))
            where !found.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
                let name = (text as NSString).substring(with: match.range(at: 1))
                found.append((match.range, MarkupTag(name: name, value: MarkupTag.unknownValue)))
            }
        }
        let sources = tagSources
        for (match, tag) in found.sorted(by: { $0.range.location > $1.range.location }) {
            let range = NSRange(location: contents.location + match.location, length: match.length)
            let touched = edit.length > 0
                ? NSIntersectionRange(range, edit).length > 0
                : range.location < edit.location && edit.location < NSMaxRange(range)
            guard touched, string.rangeOfCharacter(from: CharacterSet(charactersIn: "\u{FFFC}"), range: range).location == NSNotFound,
                  !isInlineCode(range), !followsUnclosedBacktick(range, in: contents)
            else { continue }

            let selection = textView.selectedRange()
            let shown = sources.map { tag.updated(from: $0) } ?? tag
            replaceCharacters(in: range, with: shown.attachmentString(
                attributes: storage.attributes(at: range.location, effectiveRange: nil)))
            let caret = selection.location >= NSMaxRange(range) ? selection.location - range.length + 1
                : selection.location > range.location ? range.location + 1
                : selection.location
            textView.setSelectedRange(NSRange(location: caret, length: 0))
        }
    }
}

/// The variable popover: "Variable:" with a combo box offering the names in
/// `variables.txt` (any other name can be typed), and an Insert button.
final class VariableController: NSViewController, NSComboBoxDelegate {
    let comboBox = NSComboBox()
    let insertButton = NSButton(title: "Insert", target: nil, action: nil)
    private let names: [String]
    private let onInsert: (String) -> Void

    init(names: [String], onInsert: @escaping (String) -> Void) {
        self.names = names
        self.onInsert = onInsert
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        comboBox.addItems(withObjectValues: names)
        comboBox.completes = true
        comboBox.numberOfVisibleItems = 12
        comboBox.placeholderString = names.isEmpty ? "No variables.txt" : nil
        comboBox.widthAnchor.constraint(equalToConstant: 200).isActive = true

        insertButton.target = self
        insertButton.action = #selector(insert(_:))
        insertButton.keyEquivalent = "\r"

        let row = NSStackView(views: [NSTextField(labelWithString: "Variable:"), comboBox])
        row.spacing = 6
        let stack = NSStackView(views: [row, insertButton])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        // A margin around the controls. The popover ignores a stack view's
        // edge insets.
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
        view = container
        preferredContentSize = container.fittingSize
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(comboBox)
    }

    /// The name typed or chosen, if it can be a variable's.
    var name: String? {
        let name = comboBox.stringValue.trimmingCharacters(in: .whitespaces)
        return MarkupTag.isValid(name: name) ? name : nil
    }

    @objc func insert(_ sender: Any?) {
        guard let name else {
            NSSound.beep()
            return
        }
        dismiss(nil)
        onInsert(name)
    }
}

/// The citation popover: the bibliography's entries, by section, and a
/// Cite button.
final class CitationController: NSViewController {
    let entries: [Bibliography.Entry]
    let popUp = NSPopUpButton()
    let citeButton = NSButton(title: "Cite", target: nil, action: nil)
    private let bibliography: Bibliography?
    private let onCite: (String) -> Void

    init(bibliography: Bibliography?, onCite: @escaping (String) -> Void) {
        self.bibliography = bibliography
        entries = bibliography?.entries ?? []
        self.onCite = onCite
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        popUp.autoenablesItems = false
        var index = 0
        for section in bibliography?.sections ?? [] {
            // Each section's title heads its entries.
            if let title = section.title {
                if popUp.numberOfItems > 0 { popUp.menu?.addItem(.separator()) }
                popUp.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "").isEnabled = false
            }
            for entry in section.entries {
                let text = InlineMarkdown.spans(in: entry.text).map(\.text).joined()
                let item = NSMenuItem(title: "[\(entry.number)] \(text)", action: nil, keyEquivalent: "")
                item.indentationLevel = section.title == nil ? 0 : 1
                item.tag = index
                index += 1
                popUp.menu?.addItem(item)
            }
        }
        if entries.isEmpty {
            popUp.addItem(withTitle: bibliography == nil ? "No bibliography.txt" : "No Entries")
            popUp.lastItem?.isEnabled = false
        } else {
            popUp.select(popUp.menu?.items.first { $0.isEnabled })
        }
        (popUp.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        popUp.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true

        citeButton.target = self
        citeButton.action = #selector(cite(_:))
        citeButton.keyEquivalent = "\r"
        citeButton.isEnabled = !entries.isEmpty

        let title = NSTextField(labelWithString: "Insert Citation")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let row = NSStackView(views: [NSTextField(labelWithString: "Entry:"), popUp])
        row.spacing = 6
        let stack = NSStackView(views: [title, row, citeButton])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        // A margin around the controls. The popover ignores a stack view's
        // edge insets.
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            // The title on the left, the controls on the right.
            title.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
        ])
        view = container
        preferredContentSize = container.fittingSize
    }

    /// The entry chosen.
    var selectedEntry: Bibliography.Entry? {
        guard let item = popUp.selectedItem, item.isEnabled, entries.indices.contains(item.tag) else { return nil }
        return entries[item.tag]
    }

    @objc func cite(_ sender: Any?) {
        guard let entry = selectedEntry else { return }
        if presentingViewController != nil { dismiss(self) }
        onCite(entry.key)
    }
}
