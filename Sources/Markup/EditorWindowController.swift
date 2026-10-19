import AppKit
import MarkupCore

/// A document window: a header strip with the style popup, above the editor.
///
/// The text view never contains Markdown markers. Each line's style lives in
/// attributes on its characters: `.blockStyle` for headings, and for list
/// items an attachment character at the start of the line (`.listMarker`)
/// plus `.listLevel`. `markdown` turns these back into Markdown.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSTextStorageDelegate {
    static let headerHeight: CGFloat = 44

    let headerView = NSVisualEffectView()
    let stylePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    let viewModeControl = NSSegmentedControl()
    let boldButton = NSButton(image: NSImage(systemSymbolName: "bold", accessibilityDescription: "Bold")!,
                              target: nil, action: nil)
    let italicButton = NSButton(image: NSImage(systemSymbolName: "italic", accessibilityDescription: "Italic")!,
                                target: nil, action: nil)
    let strikethroughButton = NSButton(
        image: NSImage(systemSymbolName: "strikethrough", accessibilityDescription: "Strikethrough")!, target: nil, action: nil)
    let codeButton = NSButton(
        image: NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Code")!,
        target: nil, action: nil)
    let subscriptButton = NSButton(
        image: NSImage(systemSymbolName: "textformat.subscript", accessibilityDescription: "Subscript")!,
        target: nil, action: nil)
    let superscriptButton = NSButton(
        image: NSImage(systemSymbolName: "textformat.superscript", accessibilityDescription: "Superscript")!,
        target: nil, action: nil)
    let imageButton = NSButton(image: NSImage(systemSymbolName: "photo", accessibilityDescription: "Insert Image")!,
                               target: nil, action: nil)
    let textView = EditorTextView(usingTextLayoutManager: false)

    /// True when the text view shows the raw Markdown instead of the
    /// formatted text. Formatting, shortcuts and list commands are off then.
    var isShowingMarkdown = false

    /// The range of the text inserted by the edit in progress, recorded when
    /// the text view asks to change the text and acted on once it has.
    private var pendingEdit: NSRange?

    /// True while the controller is changing the text itself, so its own
    /// changes aren't treated as typing.
    private var isAdjustingText = false

    /// A style chosen for an empty last line, which has no characters to
    /// carry it, and the line's location. It applies while the caret stays
    /// there, and is forgotten once the caret is anywhere else.
    var emptyLineStyle: (location: Int, style: BlockStyle)?

    /// The code block fence for `emptyLineStyle`, when that is code.
    var emptyLineFence: CodeFence?

    /// Inline styles chosen with the buttons while nothing is selected, and
    /// the caret location they apply to. Forgotten once the caret moves.
    var typingStyles: (location: Int, styles: Set<InlineStyle>)?

    /// Where the images directory comes from.
    var settings = Settings.shared

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 480, height: 320)
        window.center()

        super.init(window: window)

        headerView.material = .headerView
        headerView.blendingMode = .withinWindow

        for style in BlockStyle.allCases {
            stylePopUp.addItem(withTitle: style.title)
            stylePopUp.lastItem?.tag = style.rawValue
        }
        stylePopUp.target = self
        stylePopUp.action = #selector(styleChosen(_:))
        stylePopUp.selectItem(withTag: BlockStyle.paragraph.rawValue)

        for (button, action, tip) in [(boldButton, #selector(toggleBold(_:)), "Bold (⌘B)"),
                                      (italicButton, #selector(toggleItalic(_:)), "Italic (⌘I)"),
                                      (strikethroughButton, #selector(toggleStrikethrough(_:)), "Strikethrough (⇧⌘X)"),
                                      (codeButton, #selector(toggleCode(_:)), "Code (⌘E)"),
                                      (subscriptButton, #selector(toggleSubscript(_:)), "Subscript (⌃⌘-)"),
                                      (superscriptButton, #selector(toggleSuperscript(_:)), "Superscript (⌃⌘=)")] {
            button.setButtonType(.pushOnPushOff)
            button.target = self
            button.action = action
            button.toolTip = tip
        }

        imageButton.target = self
        imageButton.action = #selector(insertImage(_:))
        imageButton.toolTip = "Insert Image"

        viewModeControl.segmentCount = 2
        viewModeControl.setLabel("Formatted", forSegment: 0)
        viewModeControl.setLabel("Markdown", forSegment: 1)
        viewModeControl.trackingMode = .selectOne
        viewModeControl.selectedSegment = 0
        viewModeControl.target = self
        viewModeControl.action = #selector(viewModeChosen(_:))

        let divider = NSBox()
        divider.boxType = .separator

        let scrollView = makeScrollView()

        let contentView = NSView()
        for view in [headerView, divider, scrollView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        for control in [stylePopUp, boldButton, italicButton, strikethroughButton, codeButton, subscriptButton, superscriptButton,
                        imageButton, viewModeControl] {
            control.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(control)
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            stylePopUp.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            stylePopUp.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            boldButton.leadingAnchor.constraint(equalTo: stylePopUp.trailingAnchor, constant: 8),
            boldButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            italicButton.leadingAnchor.constraint(equalTo: boldButton.trailingAnchor, constant: 4),
            italicButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            strikethroughButton.leadingAnchor.constraint(equalTo: italicButton.trailingAnchor, constant: 4),
            strikethroughButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            codeButton.leadingAnchor.constraint(equalTo: strikethroughButton.trailingAnchor, constant: 4),
            codeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            subscriptButton.leadingAnchor.constraint(equalTo: codeButton.trailingAnchor, constant: 4),
            subscriptButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            superscriptButton.leadingAnchor.constraint(equalTo: subscriptButton.trailingAnchor, constant: 4),
            superscriptButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            imageButton.trailingAnchor.constraint(equalTo: viewModeControl.leadingAnchor, constant: -8),
            imageButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            viewModeControl.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            viewModeControl.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            divider.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        window.contentView = contentView
        window.initialFirstResponder = textView
        window.delegate = self
        textView.delegate = self
        storage.delegate = self
        textView.markerClickHandler = { [unowned self] index in toggleCheckbox(at: index) }
        textView.plainTextForCopy = { [unowned self] range in plainText(for: range) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The text view uses TextKit 1, whose layout manager can locate list
    /// markers for clicks.
    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        // The text view and the scroll view both start with no size. Layout
        // then widens the scroll view to fit the window, and autoresizing
        // widens the text view by the same amount, so the two stay equally
        // wide and lines wrap at the window's edge.
        // Draws the shading behind code blocks.
        textView.textContainer?.replaceLayoutManager(EditorLayoutManager())
        textView.frame = .zero
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        // The document is plain text (eventually Markdown), so turn off rich
        // text and the substitutions that would rewrite Markdown syntax.
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.applyCheckingDefaults()

        textView.typingAttributes = BlockStyle.paragraph.attributes
        textView.textContainerInset = NSSize(width: 24, height: 24)

        scrollView.documentView = textView
        return scrollView
    }

    var storage: NSTextStorage { textView.textStorage! }

    // MARK: - Lines

    /// The line containing `location`, including its newline.
    func lineRange(at location: Int) -> NSRange {
        (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
    }

    /// The lines that `range` touches.
    func lineRanges(in range: NSRange) -> [NSRange] {
        let string = storage.string as NSString
        let span = string.paragraphRange(for: range)
        var lines: [NSRange] = []
        var location = span.location
        while location < NSMaxRange(span) {
            let line = string.paragraphRange(for: NSRange(location: location, length: 0))
            lines.append(line)
            location = NSMaxRange(line)
        }
        return lines
    }

    /// `line` without its newline.
    func contentsRange(of line: NSRange) -> NSRange {
        var contentsEnd = 0
        (storage.string as NSString).getParagraphStart(nil, end: nil, contentsEnd: &contentsEnd,
                                                      for: NSRange(location: line.location, length: 0))
        return NSRange(location: line.location, length: contentsEnd - line.location)
    }

    /// The list item that `line` is, if it starts with a list marker.
    func listItem(at line: NSRange) -> ListItem? {
        guard line.length > 0,
              let raw = storage.attribute(.listMarker, at: line.location, effectiveRange: nil) as? Int,
              let marker = ListMarker(rawValue: raw) else { return nil }
        let level = storage.attribute(.listLevel, at: line.location, effectiveRange: nil) as? Int ?? 0
        return ListItem(level: level, marker: marker)
    }

    // MARK: - Undoable changes

    /// Replaces text the way typing would: undoably, and with the text view
    /// told before and after.
    func replaceCharacters(in range: NSRange, with text: NSAttributedString) {
        textView.breakUndoCoalescing()
        isAdjustingText = true
        defer { isAdjustingText = false }
        guard textView.shouldChangeText(in: range, replacementString: text.string) else { return }
        storage.replaceCharacters(in: range, with: text)
        textView.didChangeText()
    }

    /// Runs `change`, which may change only attributes within `range`, and
    /// registers an undo that puts the previous attributes back.
    func changeAttributes(in range: NSRange, _ change: () -> Void) {
        let previous = storage.attributedSubstring(from: range)
        storage.beginEditing()
        change()
        storage.endEditing()
        registerUndo(restoring: previous, at: range.location)
    }

    /// Puts back the attributes of `attributed` over the same span of text,
    /// registering the reverse so the change can be redone.
    private func restoreAttributes(_ attributed: NSAttributedString, at location: Int) {
        let range = NSRange(location: location, length: attributed.length)
        guard NSMaxRange(range) <= storage.length else { return }
        changeAttributes(in: range) {
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, run, _ in
                storage.setAttributes(attributes, range: NSRange(location: location + run.location, length: run.length))
            }
        }
        updateForSelection()
    }

    private func registerUndo(restoring attributed: NSAttributedString, at location: Int) {
        guard let undoManager else { return }
        // Stop NSTextView extending an earlier typing undo past this change,
        // which would leave this undo pointing at text that has moved.
        textView.breakUndoCoalescing()
        nonisolated(unsafe) let attributed = attributed
        undoManager.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated {
                controller.restoreAttributes(attributed, at: location)
            }
        }
    }

    // MARK: - NSTextViewDelegate

    func textViewDidChangeSelection(_ notification: Notification) {
        updateForSelection()
    }

    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange oldRange: NSRange,
                  toCharacterRange newRange: NSRange) -> NSRange {
        isShowingMarkdown ? newRange : adjustSelectionAroundListMarker(from: oldRange, to: newRange)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !isShowingMarkdown else { return false }
        return switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            insertNewlineInList() || insertNewlineAfterHeading() || insertNewlineInCode()
        case #selector(NSResponder.insertTab(_:)):
            changeListLevel(by: 1)
        case #selector(NSResponder.insertBacktab(_:)):
            changeListLevel(by: -1)
        default:
            false
        }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        if let replacementString, !isAdjustingText {
            pendingEdit = NSRange(location: affectedCharRange.location, length: (replacementString as NSString).length)
        }
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard let edit = pendingEdit, !isAdjustingText else { return }
        pendingEdit = nil
        guard !isShowingMarkdown, let undoManager, !undoManager.isUndoing, !undoManager.isRedoing else { return }
        applyMarkdownShortcuts(after: edit)
        updateForSelection()
    }

    // MARK: - NSTextStorageDelegate

    /// Keeps every line consistent after an edit. A list line (one starting
    /// with a marker) has its item's attributes throughout. Any other line
    /// has a single block style throughout, taken from its first character,
    /// and no list attributes. This is what turns two joined lines into one
    /// line in the first line's style, and a line whose marker was deleted
    /// back into a paragraph.
    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                 range editedRange: NSRange, changeInLength delta: Int) {
        MainActor.assumeIsolated {
            guard editedMask.contains(.editedCharacters), !isShowingMarkdown, let undoManager,
                  !undoManager.isUndoing, !undoManager.isRedoing else { return }
            for line in lineRanges(in: editedRange) where line.length > 0 {
                if let item = listItem(at: line) {
                    if !hasUniform(.listLevel, item.level, in: line) || !hasUniform(.blockStyle, 0, in: line)
                        || contains(.codeFence, in: line) {
                        changeAttributes(in: line) {
                            storage.addAttributes(item.lineAttributes, range: line)
                            storage.removeAttribute(.codeFence, range: line)
                            storage.applyInlineStyles(in: line)
                        }
                    }
                } else {
                    let style = storage.blockStyle(at: line.location)
                    // Code keeps its text as typed, so it has no inline
                    // styles, and the whole line has its first character's
                    // fence.
                    let fence = style == .code ? storage.attribute(.codeFence, at: line.location, effectiveRange: nil) as? CodeFence : nil
                    let hasInlineStyles = style == .code && InlineStyle.allCases.contains { contains($0.key, in: line) }
                    if !hasUniform(.blockStyle, style.rawValue, in: line) || contains(.listLevel, in: line)
                        || !hasUniformFence(fence, in: line) || hasInlineStyles {
                        changeAttributes(in: line) {
                            storage.addAttributes(style.attributes, range: line)
                            storage.removeAttribute(.listLevel, range: line)
                            storage.removeAttribute(.codeFence, range: line)
                            if let fence { storage.addAttribute(.codeFence, value: fence, range: line) }
                            if style == .code {
                                for inlineStyle in InlineStyle.allCases {
                                    storage.removeAttribute(inlineStyle.key, range: line)
                                }
                            }
                            storage.applyInlineStyles(in: line)
                        }
                    }
                }
            }
        }
    }

    private func hasUniform(_ key: NSAttributedString.Key, _ value: Int, in range: NSRange) -> Bool {
        var isUniform = true
        storage.enumerateAttribute(key, in: range) { found, _, stop in
            if (found as? Int) != value {
                isUniform = false
                stop.pointee = true
            }
        }
        return isUniform
    }

    private func hasUniformFence(_ fence: CodeFence?, in range: NSRange) -> Bool {
        var isUniform = true
        storage.enumerateAttribute(.codeFence, in: range) { found, _, stop in
            if found as? CodeFence != fence {
                isUniform = false
                stop.pointee = true
            }
        }
        return isUniform
    }

    private func contains(_ key: NSAttributedString.Key, in range: NSRange) -> Bool {
        var found = false
        storage.enumerateAttribute(key, in: range) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: - NSWindowDelegate

    var markdownDocument: MarkdownDocument? {
        document as? MarkdownDocument
    }

    // Typing and style changes register undo on the document's undo manager,
    // which is how the document tracks unsaved changes.
    override var undoManager: UndoManager? {
        markdownDocument?.undoManager
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        undoManager
    }
}
