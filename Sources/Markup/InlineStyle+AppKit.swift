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
    /// True on subscript characters (`H~2~O`).
    static let inlineSubscript = NSAttributedString.Key("MarkupInlineSubscript")
    /// True on superscript characters (`x^2^`).
    static let inlineSuperscript = NSAttributedString.Key("MarkupInlineSuperscript")
    /// True on highlighted characters (`==highlight==`).
    static let inlineHighlight = NSAttributedString.Key("MarkupInlineHighlight")
    /// The destination, a String, on the characters of a link's text
    /// (`[text](destination)`).
    static let markdownLink = NSAttributedString.Key("MarkupLink")

    /// Everything that formats text within a line: the inline styles and
    /// links. Code blocks have none of it.
    static let inlineFormatting = InlineStyle.allCases.map(\.key) + [.markdownLink]
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
        case .highlight: .inlineHighlight
        }
    }

    /// The colour of links: navy, or in dark mode, where navy can't be read,
    /// a light navy blue.
    static let linkColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.55, green: 0.65, blue: 1, alpha: 1) : NSColor(srgbRed: 0, green: 0, blue: 0.5, alpha: 1)
    }

    /// The background of highlighted text, like a highlighter pen: yellow,
    /// or in dark mode a dimmer yellow that light text can be read on.
    static let highlightColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.6, green: 0.5, blue: 0, alpha: 0.75) : NSColor(srgbRed: 1, green: 0.93, blue: 0.25, alpha: 1)
    }

    /// The background of a link to a heading that isn't there, like
    /// highlighting but red: a light red, or in dark mode a dimmer red that
    /// light text can be read on.
    static let brokenLinkColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.7, green: 0.15, blue: 0.15, alpha: 0.75) : NSColor(srgbRed: 1, green: 0.6, blue: 0.6, alpha: 1)
    }

    /// The background behind text with `styles`, if any. Highlight wins
    /// over code's shading.
    static func background(for styles: Set<InlineStyle>) -> NSColor? {
        styles.contains(.highlight) ? highlightColor : styles.contains(.code) ? codeBackground : nil
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
    /// These attributes with just `styles` and `link`, and the font,
    /// strikethrough, shading, baseline offset and link colour to show them.
    func withInlineStyles(_ styles: Set<InlineStyle>, link: String? = nil) -> [NSAttributedString.Key: Any] {
        var attributes = self
        for style in InlineStyle.allCases {
            attributes[style.key] = styles.contains(style) ? true : nil
        }
        let blockStyle = (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
        attributes[.font] = blockStyle.font(for: styles.union(attributes[.tableHeader] != nil ? [.bold] : []))
        attributes[.strikethroughStyle] = styles.contains(.strikethrough) ? NSUnderlineStyle.single.rawValue : nil
        attributes[.backgroundColor] = InlineStyle.background(for: styles)
        attributes[.baselineOffset] = blockStyle.baselineOffset(for: styles)
        attributes[.markdownLink] = link
        attributes[.foregroundColor] = link == nil ? NSColor.textColor : InlineStyle.linkColor
        attributes[.underlineStyle] = link == nil ? nil : NSUnderlineStyle.single.rawValue
        attributes[.toolTip] = link
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
    /// Sets the font, strikethrough, shading, baseline offset and link colour
    /// of every character in `range` from its line's style, its inline
    /// styles and its link. A table's header cells are bold.
    /// Needed wherever a line's style is set, since that sets the plain font.
    func applyInlineStyles(in range: NSRange) {
        enumerateAttributes(in: range) { attributes, run, _ in
            let style = (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
            let styles = Set(InlineStyle.allCases.filter { attributes[$0.key] != nil })
            let font = style.font(for: styles.union(attributes[.tableHeader] != nil ? [.bold] : []))
            if attributes[.font] as? NSFont != font {
                addAttribute(.font, value: font, range: run)
            }
            if attributes[.inlineStrikethrough] != nil {
                addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: run)
            } else if attributes[.strikethroughStyle] != nil {
                removeAttribute(.strikethroughStyle, range: run)
            }
            if let background = InlineStyle.background(for: styles) {
                if attributes[.backgroundColor] as? NSColor != background {
                    addAttribute(.backgroundColor, value: background, range: run)
                }
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
            if let link = attributes[.markdownLink] as? String {
                if attributes[.toolTip] as? String != link {
                    addAttributes([.foregroundColor: InlineStyle.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .toolTip: link], range: run)
                }
            } else if let tag = attributes[.markupTag] as? MarkupTag {
                if attributes[.toolTip] as? String != tag.toolTip {
                    addAttribute(.toolTip, value: tag.toolTip, range: run)
                }
            } else if attributes[.toolTip] != nil {
                // Was a link.
                addAttribute(.foregroundColor, value: NSColor.textColor, range: run)
                removeAttribute(.underlineStyle, range: run)
                removeAttribute(.toolTip, range: run)
            }
        }
    }
}
