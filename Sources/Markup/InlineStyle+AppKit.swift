import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// True on bold characters (`**bold**`).
    static let inlineBold = NSAttributedString.Key("MarkupInlineBold")
    /// True on italic characters (`*italic*`).
    static let inlineItalic = NSAttributedString.Key("MarkupInlineItalic")
    /// True on struck-through characters (`~~strikethrough~~`).
    static let inlineStrikethrough = NSAttributedString.Key("MarkupInlineStrikethrough")
}

extension InlineStyle {
    /// The attribute that marks text with this style.
    var key: NSAttributedString.Key {
        switch self {
        case .bold: .inlineBold
        case .italic: .inlineItalic
        case .strikethrough: .inlineStrikethrough
        }
    }
}

extension BlockStyle {
    /// The style's font, made bold and/or italic.
    func font(bold: Bool, italic: Bool) -> NSFont {
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        guard traits != font.fontDescriptor.symbolicTraits else { return font }
        return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
    }
}

extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    /// These attributes with just `styles`, and the font and strikethrough
    /// to show them.
    func withInlineStyles(_ styles: Set<InlineStyle>) -> [NSAttributedString.Key: Any] {
        var attributes = self
        for style in InlineStyle.allCases {
            attributes[style.key] = styles.contains(style) ? true : nil
        }
        let blockStyle = (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
        attributes[.font] = blockStyle.font(bold: styles.contains(.bold), italic: styles.contains(.italic))
        attributes[.strikethroughStyle] = styles.contains(.strikethrough) ? NSUnderlineStyle.single.rawValue : nil
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
    /// Sets the font and strikethrough of every character in `range` from
    /// its line's style and its inline styles. Needed wherever a line's
    /// style is set, since that sets the plain font.
    func applyInlineStyles(in range: NSRange) {
        enumerateAttributes(in: range) { attributes, run, _ in
            let style = (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
            let font = style.font(bold: attributes[.inlineBold] != nil, italic: attributes[.inlineItalic] != nil)
            if attributes[.font] as? NSFont != font {
                addAttribute(.font, value: font, range: run)
            }
            if attributes[.inlineStrikethrough] != nil {
                addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: run)
            } else if attributes[.strikethroughStyle] != nil {
                removeAttribute(.strikethroughStyle, range: run)
            }
        }
    }
}
