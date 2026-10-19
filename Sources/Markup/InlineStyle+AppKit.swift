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
}

extension InlineStyle {
    /// The attribute that marks text with this style.
    var key: NSAttributedString.Key {
        switch self {
        case .bold: .inlineBold
        case .italic: .inlineItalic
        case .strikethrough: .inlineStrikethrough
        case .code: .inlineCode
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
    /// and monospaced (a little smaller) for code.
    func font(for styles: Set<InlineStyle>) -> NSFont {
        let base = styles.contains(.code) ? NSFont.monospacedSystemFont(ofSize: round(font.pointSize * 0.9), weight: .regular)
            : font
        var traits = base.fontDescriptor.symbolicTraits
        if styles.contains(.bold) { traits.insert(.bold) }
        if styles.contains(.italic) { traits.insert(.italic) }
        guard traits != base.fontDescriptor.symbolicTraits else { return base }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: base.pointSize) ?? base
    }
}

extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    /// These attributes with just `styles`, and the font, strikethrough and
    /// shading to show them.
    func withInlineStyles(_ styles: Set<InlineStyle>) -> [NSAttributedString.Key: Any] {
        var attributes = self
        for style in InlineStyle.allCases {
            attributes[style.key] = styles.contains(style) ? true : nil
        }
        let blockStyle = (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
        attributes[.font] = blockStyle.font(for: styles)
        attributes[.strikethroughStyle] = styles.contains(.strikethrough) ? NSUnderlineStyle.single.rawValue : nil
        attributes[.backgroundColor] = styles.contains(.code) ? InlineStyle.codeBackground : nil
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
    /// Sets the font, strikethrough and shading of every character in
    /// `range` from its line's style and its inline styles. Needed wherever
    /// a line's style is set, since that sets the plain font.
    func applyInlineStyles(in range: NSRange) {
        enumerateAttributes(in: range) { attributes, run, _ in
            let style = (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
            let font = style.font(for: Set(InlineStyle.allCases.filter { attributes[$0.key] != nil }))
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
        }
    }
}
