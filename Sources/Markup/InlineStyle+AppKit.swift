import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// True on bold characters (`**bold**`).
    static let inlineBold = NSAttributedString.Key("MarkupInlineBold")
    /// True on italic characters (`*italic*`).
    static let inlineItalic = NSAttributedString.Key("MarkupInlineItalic")
    /// True on struck-through characters (`~~strikethrough~~`).
    static let inlineStrikethrough = NSAttributedString.Key("MarkupInlineStrikethrough")
    /// True on inline code characters (`` `code` ``).
    static let inlineCode = NSAttributedString.Key("MarkupInlineCode")
    /// True on subscript characters (`H_2_O`).
    static let inlineSubscript = NSAttributedString.Key("MarkupInlineSubscript")
    /// True on superscript characters (`x^2^`).
    static let inlineSuperscript = NSAttributedString.Key("MarkupInlineSuperscript")
}

extension InlineStyle {
    /// The attribute that marks text with this style.
    var key: NSAttributedString.Key {
        switch self {
        case .bold: .inlineBold
        case .italic: .inlineItalic
        case .strikethrough: .inlineStrikethrough
        case .code: .inlineCode
        case .subscript: .inlineSubscript
        case .superscript: .inlineSuperscript
        }
    }

    /// The shading behind inline code: a light grey, or in dark mode a dark
    /// one.
    static let codeBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.07)
    }
}

extension BlockStyle {
    /// The font for text in this style with `styles`: bold and/or italic,
    /// monospaced (a little smaller) for code, and smaller for subscript and
    /// superscript.
    func font(for styles: Set<InlineStyle>) -> NSFont {
        var base = styles.contains(.code) ? NSFont.monospacedSystemFont(ofSize: round(font.pointSize * 0.9), weight: .regular)
            : font
        if !styles.isDisjoint(with: [.subscript, .superscript]) {
            base = NSFont(descriptor: base.fontDescriptor, size: round(base.pointSize * 0.75)) ?? base
        }
        var traits = base.fontDescriptor.symbolicTraits
        if styles.contains(.bold) { traits.insert(.bold) }
        if styles.contains(.italic) { traits.insert(.italic) }
        guard traits != base.fontDescriptor.symbolicTraits else { return base }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: base.pointSize) ?? base
    }

    /// How far text in this style with `styles` is raised (superscript) or
    /// lowered (subscript), if at all. Superscript wins if both are set.
    func baselineOffset(for styles: Set<InlineStyle>) -> CGFloat? {
        if styles.contains(.superscript) { return round(font.pointSize * 0.35) }
        if styles.contains(.subscript) { return -round(font.pointSize * 0.15) }
        return nil
    }
}

extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    /// These attributes with just `styles`, and the font, strikethrough,
    /// shading and baseline offset to show them.
    func withInlineStyles(_ styles: Set<InlineStyle>) -> [NSAttributedString.Key: Any] {
        var attributes = self
        for style in InlineStyle.allCases {
            attributes[style.key] = styles.contains(style) ? true : nil
        }
        let blockStyle = (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
        attributes[.font] = blockStyle.font(for: styles)
        attributes[.strikethroughStyle] = styles.contains(.strikethrough) ? NSUnderlineStyle.single.rawValue : nil
        attributes[.backgroundColor] = styles.contains(.code) ? InlineStyle.codeBackground : nil
        attributes[.baselineOffset] = blockStyle.baselineOffset(for: styles)
        return attributes
    }
}

extension NSAttributedString {
    func inlineStyles(at index: Int) -> Set<InlineStyle> {
        Set(InlineStyle.allCases.filter { attribute($0.key, at: index, effectiveRange: nil) != nil })
    }

    func isBold(at index: Int) -> Bool {
        inlineStyles(at: index).contains(.bold)
    }

    func isItalic(at index: Int) -> Bool {
        inlineStyles(at: index).contains(.italic)
    }
}

extension NSMutableAttributedString {
    /// Sets the font, strikethrough, shading and baseline offset of every
    /// character in `range` from its line's style and its inline styles.
    /// Needed wherever a line's style is set, since that sets the plain font.
    func applyInlineStyles(in range: NSRange) {
        enumerateAttributes(in: range) { attributes, run, _ in
            let style = (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
            let styles = Set(InlineStyle.allCases.filter { attributes[$0.key] != nil })
            let font = style.font(for: styles)
            if attributes[.font] as? NSFont != font {
                addAttribute(.font, value: font, range: run)
            }
            if attributes[.inlineStrikethrough] != nil {
                addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: run)
            } else if attributes[.strikethroughStyle] != nil {
                removeAttribute(.strikethroughStyle, range: run)
            }
            if attributes[.inlineCode] != nil {
                addAttribute(.backgroundColor, value: InlineStyle.codeBackground, range: run)
            } else if attributes[.backgroundColor] != nil {
                removeAttribute(.backgroundColor, range: run)
            }
            if let offset = style.baselineOffset(for: styles) {
                if attributes[.baselineOffset] as? CGFloat != offset {
                    addAttribute(.baselineOffset, value: offset, range: run)
                }
            } else if attributes[.baselineOffset] != nil {
                removeAttribute(.baselineOffset, range: run)
            }
        }
    }
}
