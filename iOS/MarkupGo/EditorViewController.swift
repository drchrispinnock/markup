import MarkupCore
import UIKit

/// Edits one Markdown file: paragraphs, headings and code blocks, with bold,
/// italic, strikethrough and inline code. Other Markdown is shown as its
/// source (`FormattedText`).
///
/// As on the Mac, the text has no markers. Every character of a line carries
/// its style, and after each edit `normalize(_:)` gives a line the style of
/// its first character. A line with no characters, the empty last line,
/// takes its style from `pendingStyle` if one was chosen there.
final class EditorViewController: UIViewController {
    let file: MarkdownFile?
    let textView: UITextView
    var storage: NSTextStorage { textView.textStorage }

    /// A style chosen on the empty last line, which has no characters to
    /// carry it, kept while the caret stays there.
    var pendingStyle: (location: Int, style: BlockStyle, fence: CodeFence?)?
    /// Set while the editor makes a text change of its own, which the
    /// delegate lets through as is.
    private var isChangingText = false
    /// The location after a space just typed, which may end a `# `.
    private var typedSpace: Int?

    private lazy var styleItem = UIBarButtonItem(title: BlockStyle.paragraph.menuTitle, menu: styleMenu())
    private var inlineItems: [InlineStyle: UIBarButtonItem] = [:]

    init(file: MarkdownFile?, markdown: String) {
        self.file = file
        let storage = NSTextStorage()
        let layoutManager = CodeLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        textView = UITextView(frame: .zero, textContainer: container)
        super.init(nibName: nil, bundle: nil)
        storage.delegate = self
        load(markdown: markdown)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Views

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        textView.delegate = self
        textView.backgroundColor = .systemBackground
        textView.allowsEditingTextAttributes = false
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 24, right: 12)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.inputAccessoryView = makeToolbar()
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        connectFile()
        updateForSelection()
    }

    private func makeToolbar() -> UIToolbar {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        var items: [UIBarButtonItem] = [styleItem, .flexibleSpace()]
        let buttons: [(InlineStyle, String, String)] = [
            (.bold, "bold", "Bold"), (.italic, "italic", "Italic"),
            (.strikethrough, "strikethrough", "Strikethrough"), (.code, "chevron.left.forwardslash.chevron.right", "Code"),
        ]
        for (style, symbol, title) in buttons {
            let item = UIBarButtonItem(image: UIImage(systemName: symbol), primaryAction: UIAction(title: title) { [weak self] _ in
                self?.toggle(style)
            })
            item.accessibilityLabel = title
            inlineItems[style] = item
            items.append(item)
        }
        items += [.flexibleSpace(), UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"),
                                                   primaryAction: UIAction(title: "Hide Keyboard") { [weak self] _ in
            self?.textView.resignFirstResponder()
        })]
        toolbar.items = items
        toolbar.sizeToFit()
        return toolbar
    }

    private func styleMenu() -> UIMenu {
        UIMenu(children: BlockStyle.editable.map { style in
            UIAction(title: style.menuTitle) { [weak self] _ in self?.setStyle(style) }
        })
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(title: "Bold", action: #selector(toggleBold), input: "b", modifierFlags: .command),
            UIKeyCommand(title: "Italic", action: #selector(toggleItalic), input: "i", modifierFlags: .command),
            UIKeyCommand(title: "Strikethrough", action: #selector(toggleStrikethrough), input: "x",
                         modifierFlags: [.command, .shift]),
            UIKeyCommand(title: "Code", action: #selector(toggleCode), input: "c", modifierFlags: [.command, .shift]),
        ]
    }

    @objc func toggleBold() { toggle(.bold) }
    @objc func toggleItalic() { toggle(.italic) }
    @objc func toggleStrikethrough() { toggle(.strikethrough) }
    @objc func toggleCode() { toggle(.code) }

    // MARK: - Markdown

    func load(markdown: String) {
        storage.setAttributedString(FormattedText.attributedString(fromMarkdown: markdown))
        pendingStyle = nil
        textView.undoManager?.removeAllActions()
    }

    var markdown: String {
        FormattedText.markdown(from: storage)
    }

    // MARK: - Lines

    var string: NSString { storage.string as NSString }

    /// The line at `location`, with its newline. The empty last line is an
    /// empty range at the end.
    func lineRange(at location: Int) -> NSRange {
        if location == string.length, location == 0 || string.character(at: location - 1) == 0x0A {
            return NSRange(location: location, length: 0)
        }
        return string.lineRange(for: NSRange(location: min(location, string.length), length: 0))
    }

    func contentsRange(of line: NSRange) -> NSRange {
        FormattedText.contentsRange(of: line, in: string)
    }

    /// The lines `range` touches.
    func lineRanges(in range: NSRange) -> [NSRange] {
        var lines = [lineRange(at: range.location)]
        while NSMaxRange(lines.last!) < NSMaxRange(range) {
            lines.append(lineRange(at: NSMaxRange(lines.last!)))
        }
        return lines
    }

    /// The style of the line `line`, or of what is typed there if empty.
    func style(of line: NSRange) -> BlockStyle {
        if line.length > 0 { return storage.blockStyle(at: line.location) }
        if let pendingStyle, pendingStyle.location == line.location { return pendingStyle.style }
        return .paragraph
    }

    func isSource(_ line: NSRange) -> Bool {
        line.length > 0 && storage.sourceLine(at: line.location) != nil
    }

    // MARK: - Styles

    /// Gives the selected lines `style`. Lines shown as Markdown are left
    /// alone.
    func setStyle(_ style: BlockStyle) {
        let selection = textView.selectedRange
        for line in lineRanges(in: selection) where !isSource(line) {
            guard line.length > 0 else {
                pendingStyle = (line.location, style, nil)
                continue
            }
            changeAttributes(in: line) { text in
                text.addAttribute(.blockStyle, value: style.rawValue, range: line)
                text.addAttribute(.paragraphStyle, value: style.paragraphStyle, range: line)
                text.removeAttribute(.codeFence, range: line)
                if style == .code {
                    for key in NSAttributedString.Key.inlineFormatting { text.removeAttribute(key, range: line) }
                }
            }
        }
        textView.undoManager?.setActionName("Style")
        updateForSelection()
        file?.updateChangeCount(.done)
    }

    /// Bold, italic, strikethrough or code on the selection, or off if all of
    /// it has it already. With no selection, for what is typed next.
    func toggle(_ style: InlineStyle) {
        let selection = textView.selectedRange
        if selection.length == 0 {
            var attributes = textView.typingAttributes
            guard attributes[.sourceLine] == nil,
                  (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init) != .code else { return }
            var styles = Set(InlineStyle.allCases.filter { attributes[$0.key] != nil })
            if styles.contains(style) { styles.remove(style) } else { styles.insert(style) }
            attributes = attributes.withInlineStyles(styles, link: attributes[.markdownLink] as? String)
            let sample = NSMutableAttributedString(string: " ", attributes: attributes)
            sample.applyAppearance(in: NSRange(location: 0, length: 1))
            textView.typingAttributes = sample.attributes(at: 0, effectiveRange: nil)
            updateInlineItems(styles)
            return
        }
        // The text that can take it: not code, nor shown as Markdown.
        var ranges: [NSRange] = []
        for line in lineRanges(in: selection) where !isSource(line) && self.style(of: line) != .code {
            let range = NSIntersectionRange(contentsRange(of: line), selection)
            if range.length > 0 { ranges.append(range) }
        }
        guard !ranges.isEmpty else { return }
        let hasStyle = ranges.allSatisfy { range in
            var all = true
            storage.enumerateAttribute(style.key, in: range) { value, _, stop in
                if value == nil { all = false; stop.pointee = true }
            }
            return all
        }
        let whole = NSUnionRange(ranges.first!, ranges.last!)
        changeAttributes(in: whole) { text in
            for range in ranges {
                if hasStyle {
                    text.removeAttribute(style.key, range: range)
                } else {
                    text.addAttribute(style.key, value: true, range: range)
                    // Subscript and superscript take each other off.
                    if style == .subscript { text.removeAttribute(.inlineSuperscript, range: range) }
                    if style == .superscript { text.removeAttribute(.inlineSubscript, range: range) }
                }
            }
        }
        textView.undoManager?.setActionName(style == .code ? "Code" : "Format")
        updateForSelection()
        file?.updateChangeCount(.done)
    }

    /// Changes attributes in `range` (never the text), undoably.
    func changeAttributes(in range: NSRange, _ change: (NSTextStorage) -> Void) {
        let old = storage.attributedSubstring(from: range)
        storage.beginEditing()
        change(storage)
        storage.applyAppearance(in: range)
        storage.endEditing()
        textView.undoManager?.registerUndo(withTarget: self) { editor in
            editor.restoreAttributes(old, at: range.location)
        }
    }

    private func restoreAttributes(_ attributes: NSAttributedString, at location: Int) {
        let range = NSRange(location: location, length: attributes.length)
        guard NSMaxRange(range) <= storage.length else { return }
        changeAttributes(in: range) { text in
            attributes.enumerateAttributes(in: NSRange(location: 0, length: attributes.length)) { values, run, _ in
                text.setAttributes(values, range: NSRange(location: location + run.location, length: run.length))
            }
        }
        updateForSelection()
        file?.updateChangeCount(.done)
    }

    // MARK: - Selection

    /// Sets the typing attributes from the caret's line, and the toolbar.
    func updateForSelection() {
        let selection = textView.selectedRange
        let line = lineRange(at: selection.location)
        if let pendingStyle, pendingStyle.location != selection.location || line.length > 0 {
            self.pendingStyle = nil
        }
        let style = style(of: line)
        styleItem.title = isSource(line) ? "Markdown" : style.menuTitle
        styleItem.isEnabled = !isSource(line)
        if selection.length == 0 {
            textView.typingAttributes = typingAttributes(at: selection.location, in: line)
        }
        let styles = selection.length == 0 ? Set(InlineStyle.allCases.filter { textView.typingAttributes[$0.key] != nil })
            : selection.location < storage.length ? storage.inlineStyles(at: selection.location) : []
        updateInlineItems(styles)
        let canFormat = !isSource(line) && style != .code
        for item in inlineItems.values { item.isEnabled = canFormat || selection.length > 0 }
        updateInputTraits(forCode: style == .code || isSource(line))
    }

    private func updateInlineItems(_ styles: Set<InlineStyle>) {
        for (style, item) in inlineItems { item.isSelected = styles.contains(style) }
    }

    /// What is typed at `location` in `line` takes: the line's style, and the
    /// inline styles of the character before it on the line. A link goes on
    /// only strictly inside it.
    private func typingAttributes(at location: Int, in line: NSRange) -> [NSAttributedString.Key: Any] {
        guard line.length > 0 else {
            var attributes = style(of: line).attributes
            attributes[.codeFence] = pendingStyle?.fence
            return attributes
        }
        var attributes: [NSAttributedString.Key: Any]
        if location > line.location {
            attributes = storage.attributes(at: location - 1, effectiveRange: nil)
            let link = attributes[.markdownLink] as? String
            if link != nil, location >= NSMaxRange(contentsRange(of: line))
                || storage.attribute(.markdownLink, at: location, effectiveRange: nil) as? String != link {
                attributes[.markdownLink] = nil
            }
        } else {
            attributes = storage.attributes(at: line.location, effectiveRange: nil)
            for key in NSAttributedString.Key.inlineFormatting { attributes[key] = nil }
        }
        let sample = NSMutableAttributedString(string: " ", attributes: attributes)
        sample.applyAppearance(in: NSRange(location: 0, length: 1))
        return sample.attributes(at: 0, effectiveRange: nil)
    }

    /// Code and Markdown aren't autocorrected, capitalised or given smart
    /// quotes.
    private func updateInputTraits(forCode isCode: Bool) {
        let correction: UITextAutocorrectionType = isCode ? .no : .default
        guard textView.autocorrectionType != correction else { return }
        textView.autocorrectionType = correction
        textView.autocapitalizationType = isCode ? .none : .sentences
        textView.smartQuotesType = isCode ? .no : .default
        textView.smartDashesType = isCode ? .no : .default
        textView.spellCheckingType = isCode ? .no : .default
        if textView.isFirstResponder { textView.reloadInputViews() }
    }

    // MARK: - Editing

    /// Replaces `range` with `text` in `attributes`, as typing would, so
    /// that the text view registers the undo.
    private func replace(_ range: NSRange, with text: String, attributes: [NSAttributedString.Key: Any]) {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else { return }
        isChangingText = true
        textView.typingAttributes = attributes
        textView.replace(textRange, withText: text)
        isChangingText = false
    }

    /// Return: ends a code block on its empty last line, starts one after
    /// ```` ``` ````, and after a heading starts a paragraph. False if it was
    /// handled.
    private func handleReturn(in range: NSRange) -> Bool {
        guard range.length == 0 else { return true }
        let line = lineRange(at: range.location)
        guard !isSource(line) else { return true }
        let contents = contentsRange(of: line)
        let style = style(of: line)
        let atEnd = range.location == NSMaxRange(contents)
        switch style {
        case .code:
            guard contents.length == 0 else { return true }
            let next = NSMaxRange(line)
            let endsBlock = next >= storage.length || storage.blockStyle(at: next) != .code || isSource(lineRange(at: next))
            guard endsBlock else { return true }
            if line.length == 0 {
                pendingStyle = (line.location, .paragraph, nil)
                updateForSelection()
            } else {
                replace(line, with: "\n", attributes: BlockStyle.paragraph.attributes)
                textView.selectedRange = NSRange(location: line.location, length: 0)
            }
            return false
        case .paragraph:
            let text = string.substring(with: contents)
            guard atEnd, let fence = CodeFence(line: text) else { return true }
            // The line becomes an empty code line; at the end of the text it
            // needs a newline to carry the style.
            var attributes = BlockStyle.code.attributes
            attributes[.codeFence] = fence == CodeFence() ? nil : fence
            replace(line, with: "\n", attributes: attributes)
            textView.selectedRange = NSRange(location: line.location, length: 0)
            return false
        default:
            guard style.isHeading, atEnd else { return true }
            if line.length > contents.length {
                // An empty paragraph after the heading's newline.
                replace(NSRange(location: NSMaxRange(line), length: 0), with: "\n",
                        attributes: BlockStyle.paragraph.attributes)
                textView.selectedRange = NSRange(location: NSMaxRange(line), length: 0)
            } else {
                replace(range, with: "\n", attributes: textView.typingAttributes)
                pendingStyle = (storage.length, .paragraph, nil)
                updateForSelection()
            }
            return false
        }
    }

    /// `# ` to `###### ` typed at the start of a paragraph makes a heading.
    private func convertHeadingPrefix(endingAt location: Int) {
        let line = lineRange(at: location - 1)
        guard !isSource(line), style(of: line) != .code else { return }
        let contents = contentsRange(of: line)
        guard let (heading, length) = MarkdownCodec.headingPrefix(of: string.substring(with: contents)),
              line.location + length == location else { return }
        replace(NSRange(location: line.location, length: length), with: "", attributes: textView.typingAttributes)
        let changed = lineRange(at: line.location)
        if changed.length > 0 {
            changeAttributes(in: changed) { text in
                text.addAttribute(.blockStyle, value: heading.rawValue, range: changed)
                text.addAttribute(.paragraphStyle, value: heading.paragraphStyle, range: changed)
            }
        } else {
            pendingStyle = (changed.location, heading, nil)
        }
        textView.undoManager?.setActionName("Heading")
        updateForSelection()
    }

    /// Gives each line in `range` the line attributes of its first
    /// character, and strips inline styles from code. A heading split in two
    /// keeps its ID on the first part.
    private func normalize(_ range: NSRange) {
        let lineKeys: [NSAttributedString.Key] = [.blockStyle, .codeFence, .headingAnchor, .sourceLine, .paragraphStyle]
        let start = string.lineRange(for: NSRange(location: min(range.location, string.length), length: 0)).location
        var location = start
        let end = NSMaxRange(range)
        var previous: NSRange?
        while location < string.length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            let first = storage.attributes(at: line.location, effectiveRange: nil)
            for key in lineKeys {
                var effective = NSRange()
                let value = storage.attribute(key, at: line.location, effectiveRange: &effective)
                guard NSMaxRange(effective) < NSMaxRange(line) else { continue }
                if let value { storage.addAttribute(key, value: value, range: line) } else { storage.removeAttribute(key, range: line) }
            }
            if first[.sourceLine] != nil || storage.blockStyle(at: line.location) == .code {
                for key in NSAttributedString.Key.inlineFormatting { storage.removeAttribute(key, range: line) }
            }
            if let anchor = first[.headingAnchor] as? HeadingAnchor, let previous,
               storage.attribute(.headingAnchor, at: previous.location, effectiveRange: nil) as? HeadingAnchor == anchor,
               contentsRange(of: previous).length > 0 {
                storage.removeAttribute(.headingAnchor, range: line)
            }
            previous = line
            location = NSMaxRange(line)
            if location > end { break }
        }
        storage.applyAppearance(in: NSRange(location: start, length: location - start))
    }
}

extension EditorViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard !isChangingText, !(textView.undoManager?.isUndoing ?? false), !(textView.undoManager?.isRedoing ?? false) else {
            return true
        }
        typedSpace = text == " " ? range.location + 1 : nil
        if text == "\n" { return handleReturn(in: range) }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        if let typedSpace, typedSpace == textView.selectedRange.location {
            self.typedSpace = nil
            convertHeadingPrefix(endingAt: typedSpace)
        }
        file?.updateChangeCount(.done)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateForSelection()
    }
}

extension EditorViewController: NSTextStorageDelegate {
    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
                                 range editedRange: NSRange, changeInLength delta: Int) {
        MainActor.assumeIsolated {
            guard editedMask.contains(.editedCharacters), !(textView.undoManager?.isUndoing ?? false),
                  !(textView.undoManager?.isRedoing ?? false) else { return }
            normalize(editedRange)
        }
    }
}

/// Shades code blocks across the text's width.
final class CodeLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage, let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(InlineStyle.codeBackground.cgColor)
        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, container, glyphRange, _ in
            let index = self.characterIndexForGlyph(at: glyphRange.location)
            guard index < textStorage.length, textStorage.blockStyle(at: index) == .code,
                  textStorage.sourceLine(at: index) == nil else { return }
            context.fill(CGRect(x: origin.x, y: rect.minY + origin.y, width: container.size.width, height: rect.height))
        }
    }
}
