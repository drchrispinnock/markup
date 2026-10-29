import AppKit

/// The Markdown view's line numbers, down the left of the text: one number
/// for each line of the text, beside its first line fragment, so a line that
/// wraps is numbered once.
@MainActor
final class LineNumberRulerView: NSRulerView {
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    /// Space either side of the numbers.
    static let padding: CGFloat = 8

    private var textView: NSTextView? { clientView as? NSTextView }

    init(textView: NSTextView) {
        super.init(scrollView: nil, orientation: .verticalRuler)
        clientView = textView
        // Views don't clip by default, and the area to draw can reach past
        // the ruler, up into the editor's header.
        clipsToBounds = true
        ruleThickness = thickness(forLineCount: 1)
        NotificationCenter.default.addObserver(self, selector: #selector(textChanged(_:)),
                                               name: NSTextStorage.didProcessEditingNotification,
                                               object: textView.textStorage)
        NotificationCenter.default.addObserver(self, selector: #selector(layoutChanged(_:)),
                                               name: NSView.frameDidChangeNotification, object: textView)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Wide enough for the largest number. The width is changed after the
    /// edit, since changing it lays out the text again.
    @objc private func textChanged(_ notification: Notification) {
        needsDisplay = true
        DispatchQueue.main.async { [weak self] in self?.updateThickness() }
    }

    @objc private func layoutChanged(_ notification: Notification) {
        needsDisplay = true
    }

    func updateThickness() {
        guard let string = textView?.string else { return }
        let thickness = thickness(forLineCount: Self.lineCount(of: string))
        if thickness != ruleThickness { ruleThickness = thickness }
        needsDisplay = true
    }

    private func thickness(forLineCount count: Int) -> CGFloat {
        // At least three digits, so the text doesn't shift for short files.
        let digits = String(repeating: "8", count: max(3, String(count).count))
        let width = (digits as NSString).size(withAttributes: [.font: Self.font]).width
        return ceil(width + 2 * Self.padding)
    }

    /// The number of lines: one more than the number of newlines, so an
    /// empty last line counts.
    static func lineCount(of string: String) -> Int {
        string.utf16.reduce(1) { $0 + ($1 == 0x0A ? 1 : 0) }
    }

    override var requiredThickness: CGFloat { ruleThickness }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            return
        }
        let string = textView.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.secondaryLabelColor]
        let origin = textView.textContainerOrigin

        func draw(_ number: Int, atLineFragment fragment: NSRect) {
            let label = String(number) as NSString
            let size = label.size(withAttributes: attributes)
            // Centred on the line fragment, which is where the text sits
            // in the monospaced font.
            let y = convert(NSPoint(x: 0, y: fragment.midY + origin.y), from: textView).y
            label.draw(at: NSPoint(x: bounds.maxX - Self.padding - size.width, y: y - size.height / 2),
                       withAttributes: attributes)
        }

        // The lines level with the area to draw, across the whole text: the
        // ruler itself is left of the text, beside no glyphs.
        let area = convert(rect.intersection(bounds), to: textView)
        let visible = NSRect(x: 0, y: area.minY - origin.y, width: container.size.width, height: area.height)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let firstCharacter = layoutManager.characterIndexForGlyph(at: glyphs.location)
        var number = 1
        if firstCharacter > 0 {
            number = Self.lineCount(of: string.substring(to: firstCharacter))
        }

        var glyph = glyphs.location
        while glyph < NSMaxRange(glyphs) {
            var fragmentGlyphs = NSRange()
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragmentGlyphs)
            let character = layoutManager.characterIndexForGlyph(at: fragmentGlyphs.location)
            let startsLine = character == 0 || string.character(at: character - 1) == 0x0A
            if startsLine {
                // Lines above the visible ones were counted already.
                if character > firstCharacter { number += 1 }
                draw(number, atLineFragment: fragment)
            }
            glyph = NSMaxRange(fragmentGlyphs)
        }

        // The empty line after a final newline, or in an empty document.
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty, extra.intersects(visible) {
            draw(Self.lineCount(of: textView.string), atLineFragment: extra)
        }
    }
}
