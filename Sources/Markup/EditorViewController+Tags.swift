import AppKit
import MarkupCore

/// Tags (`MarkupTag`): each is one attachment character showing its value
/// (`TagAttachmentCell`), carrying `.markupTag`. Their values come from the
/// project's `tags.txt` and follow it: when it changes, and when the editor
/// appears, `updateTags()` sets every tag's value, as an edit that can be
/// undone. A document outside a project keeps the values it has.
///
/// Insert > Tag asks for a tag's name, offering those in `tags.txt`. With
/// the quick tags setting, `@name@` typed becomes that tag.
extension EditorViewController {
    /// The values in the project's `tags.txt`, or nil without one.
    var tagValues: [String: String]? {
        document?.project?.tagValues()
    }

    /// Sets every tag's value from the project's `tags.txt`.
    func updateTags() {
        guard let values = tagValues else { return }
        updateTags(from: values)
    }

    /// Sets every tag's value from `values`, returning whether any changed.
    /// The Markdown view's text is left alone: switching back updates it.
    @discardableResult
    func updateTags(from values: [String: String]) -> Bool {
        guard !isShowingMarkdown, !isPlainText else { return false }
        var changes: [(NSRange, MarkupTag)] = []
        storage.enumerateAttribute(.markupTag, in: NSRange(location: 0, length: storage.length)) { value, run, _ in
            guard let tag = value as? MarkupTag else { return }
            for index in run.location..<NSMaxRange(run) {
                let updated = tag.updated(from: values)
                if updated != tag { changes.append((NSRange(location: index, length: 1), updated)) }
            }
        }
        guard let first = changes.first, let last = changes.last else { return false }
        changeAttributes(in: NSUnionRange(first.0, last.0)) {
            for (range, tag) in changes {
                storage.addAttributes([.markupTag: tag, .toolTip: tag.toolTip], range: range)
            }
        }
        undoManager?.setActionName("Update Tags")
        return true
    }

    // MARK: - Inserting

    /// Insert > Tag: asks for the tag's name in a popover at the caret,
    /// then inserts the tag.
    @objc func insertTag(_ sender: Any?) {
        guard !isShowingMarkdown, !isPlainText else { return }
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let caret = textView.selectedRange()
        var rect = textView.firstRect(forCharacterRange: NSRange(location: caret.location, length: 0), actualRange: nil)
        rect = textView.convert(view.window?.convertFromScreen(rect) ?? rect, from: nil)
        rect.size.width = max(rect.width, 1)
        present(makeTagController(), asPopoverRelativeTo: rect, of: textView, preferredEdge: .maxY, behavior: .transient)
    }

    func makeTagController() -> TagController {
        TagController(names: (tagValues ?? [:]).keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }) {
            [weak self] name in self?.insertTag(named: name)
        }
    }

    /// Inserts the tag `name` at the selection, as if its Markdown had been
    /// typed.
    func insertTag(named name: String) {
        guard MarkupTag.isValid(name: name) else { return }
        let tag = MarkupTag(name: name, value: MarkupTag.unknownValue).updated(from: tagValues ?? [:])
        textView.insertText(tag.markdown, replacementRange: textView.selectedRange())
        undoManager?.setActionName("Insert Tag")
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Typed tags

    private static let quickTag = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_.@\-])@([\p{L}\p{N}_.\-]+)@"#)

    /// Replaces typed or pasted tags that the edit touched, and with the
    /// quick tags setting, `@name@`, with the tag. Its value is set from
    /// `tags.txt`, if there is one.
    func convertTags(in line: NSRange, after edit: NSRange) {
        let contents = contentsRange(of: line)
        let string = storage.string as NSString
        let text = string.substring(with: contents)
        var found = MarkupTag.tags(in: text).map { (range: NSRange(location: $0.range.lowerBound, length: $0.range.count), tag: $0.tag) }
        if settings.quickTags {
            for match in Self.quickTag.matches(in: text, range: NSRange(location: 0, length: contents.length))
            where !found.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
                let name = (text as NSString).substring(with: match.range(at: 1))
                found.append((match.range, MarkupTag(name: name, value: MarkupTag.unknownValue)))
            }
        }
        let values = tagValues
        for (match, tag) in found.sorted(by: { $0.range.location > $1.range.location }) {
            let range = NSRange(location: contents.location + match.location, length: match.length)
            let touched = edit.length > 0
                ? NSIntersectionRange(range, edit).length > 0
                : range.location < edit.location && edit.location < NSMaxRange(range)
            guard touched, string.rangeOfCharacter(from: CharacterSet(charactersIn: "\u{FFFC}"), range: range).location == NSNotFound,
                  !isInlineCode(range), !followsUnclosedBacktick(range, in: contents)
            else { continue }

            let selection = textView.selectedRange()
            let shown = values.map { tag.updated(from: $0) } ?? tag
            replaceCharacters(in: range, with: shown.attachmentString(
                attributes: storage.attributes(at: range.location, effectiveRange: nil)))
            let caret = selection.location >= NSMaxRange(range) ? selection.location - range.length + 1
                : selection.location > range.location ? range.location + 1
                : selection.location
            textView.setSelectedRange(NSRange(location: caret, length: 0))
        }
    }
}

/// The tag popover: "Tag:" with a combo box offering the names in
/// `tags.txt` (any other name can be typed), and an Insert button.
final class TagController: NSViewController, NSComboBoxDelegate {
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
        comboBox.placeholderString = names.isEmpty ? "No tags.txt" : nil
        comboBox.widthAnchor.constraint(equalToConstant: 200).isActive = true

        insertButton.target = self
        insertButton.action = #selector(insert(_:))
        insertButton.keyEquivalent = "\r"

        let row = NSStackView(views: [NSTextField(labelWithString: "Tag:"), comboBox])
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

    /// The name typed or chosen, if it can be a tag's.
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
