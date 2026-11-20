import MarkupCore
import UIKit

extension NSAttributedString.Key {
    /// The `BlockStyle` raw value of the line a character belongs to, on
    /// every character of the line, including its newline.
    static let blockStyle = NSAttributedString.Key("MarkupBlockStyle")
    /// The `CodeFence` of a code block, on every character of the block,
    /// when it isn't plain "```". A change of fence between two code lines
    /// starts a new block.
    static let codeFence = NSAttributedString.Key("MarkupCodeFence")
    /// A heading's ID and attributes (`HeadingAnchor`), on every character
    /// of the line. Not shown; only a heading writes it.
    static let headingAnchor = NSAttributedString.Key("MarkupHeadingAnchor")
    /// A `SourceLine`, on every character of a line shown as its Markdown:
    /// anything the editor doesn't format (lists, quotes, tables, front
    /// matter...).
    static let sourceLine = NSAttributedString.Key("MarkupSourceLine")

    static let inlineBold = NSAttributedString.Key("MarkupInlineBold")
    static let inlineItalic = NSAttributedString.Key("MarkupInlineItalic")
    static let inlineStrikethrough = NSAttributedString.Key("MarkupInlineStrikethrough")
    static let inlineCode = NSAttributedString.Key("MarkupInlineCode")
    static let inlineSubscript = NSAttributedString.Key("MarkupInlineSubscript")
    static let inlineSuperscript = NSAttributedString.Key("MarkupInlineSuperscript")
    static let inlineHighlight = NSAttributedString.Key("MarkupInlineHighlight")
    /// A link's destination, a String, on the characters of its text.
    static let markdownLink = NSAttributedString.Key("MarkupLink")

    /// Everything that formats text within a line. Code has none of it.
    static let inlineFormatting = InlineStyle.allCases.map(\.key) + [.markdownLink]
}

/// A line the editor shows as Markdown source, because it doesn't format
/// it: `line` as read, if it was, and `shown`, the text it was shown as.
/// Saved, lines still showing `shown` are written as `line`, exactly as
/// read, and others are read again as Markdown. An object, so that each
/// line's characters are one run, told apart from the next line's.
final class SourceLine: NSObject {
    let line: Line?
    let shown: String

    init(line: Line?, shown: String) {
        self.line = line
        self.shown = shown
    }
}

extension InlineStyle {
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

    static let linkColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.55, green: 0.65, blue: 1, alpha: 1) : UIColor(red: 0, green: 0, blue: 0.5, alpha: 1)
    }

    static let highlightColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.6, green: 0.5, blue: 0, alpha: 0.75) : UIColor(red: 1, green: 0.93, blue: 0.25, alpha: 1)
    }

    /// The shading behind code, inline and blocks.
    static let codeBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.07)
    }
}

extension BlockStyle {
    /// The styles the editor formats; other lines are shown as Markdown.
    static let editable: [BlockStyle] = [.paragraph, .heading1, .heading2, .heading3, .code]

    var font: UIFont {
        let base: UIFont = switch self {
        case .heading1: .systemFont(ofSize: 28, weight: .bold)
        case .heading2: .systemFont(ofSize: 23, weight: .bold)
        case .heading3: .systemFont(ofSize: 20, weight: .semibold)
        case .heading4: .systemFont(ofSize: 18, weight: .semibold)
        case .heading5, .heading6: .systemFont(ofSize: 17, weight: .semibold)
        case .code, .frontMatter: .monospacedSystemFont(ofSize: 15, weight: .regular)
        default: .systemFont(ofSize: 17)
        }
        return UIFontMetrics.default.scaledFont(for: base)
    }

    /// The font for text in this style with `styles`.
    func font(for styles: Set<InlineStyle>) -> UIFont {
        var base = styles.contains(.code)
            ? UIFontMetrics.default.scaledFont(for: .monospacedSystemFont(ofSize: round(font.pointSize * 0.9), weight: .regular))
            : font
        if !styles.isDisjoint(with: [.subscript, .superscript]) {
            base = base.withSize(round(base.pointSize * 0.75))
        }
        var traits = base.fontDescriptor.symbolicTraits
        if styles.contains(.bold) { traits.insert(.traitBold) }
        if styles.contains(.italic) { traits.insert(.traitItalic) }
        guard traits != base.fontDescriptor.symbolicTraits,
              let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    func baselineOffset(for styles: Set<InlineStyle>) -> CGFloat? {
        if styles.contains(.superscript) { return round(font.pointSize * 0.35) }
        if styles.contains(.subscript) { return -round(font.pointSize * 0.15) }
        return nil
    }

    /// Space above a heading, to set it off from the text before it.
    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        if isHeading { style.paragraphSpacingBefore = 6 }
        return style
    }

    /// What every character of a line in this style carries, before its
    /// inline styles.
    var attributes: [NSAttributedString.Key: Any] {
        [.blockStyle: rawValue, .font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraphStyle]
    }

    var menuTitle: String {
        switch self {
        case .paragraph: "Body"
        case .code: "Code"
        default: title
        }
    }
}

/// The font and colour of lines shown as Markdown source.
enum SourceStyle {
    static var font: UIFont {
        UIFontMetrics.default.scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
    }

    static func attributes(_ source: SourceLine) -> [NSAttributedString.Key: Any] {
        [.blockStyle: BlockStyle.paragraph.rawValue, .sourceLine: source, .font: font,
         .foregroundColor: UIColor.secondaryLabel, .paragraphStyle: NSParagraphStyle.default]
    }
}

extension NSAttributedString {
    func blockStyle(at location: Int) -> BlockStyle {
        (attribute(.blockStyle, at: location, effectiveRange: nil) as? Int).flatMap(BlockStyle.init) ?? .paragraph
    }

    func sourceLine(at location: Int) -> SourceLine? {
        attribute(.sourceLine, at: location, effectiveRange: nil) as? SourceLine
    }

    func inlineStyles(at location: Int) -> Set<InlineStyle> {
        Set(InlineStyle.allCases.filter { attribute($0.key, at: location, effectiveRange: nil) != nil })
    }
}

extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    /// These attributes with just `styles` and `link`, and the look they
    /// give.
    func withInlineStyles(_ styles: Set<InlineStyle>, link: String? = nil) -> [NSAttributedString.Key: Any] {
        var attributes = self
        for style in InlineStyle.allCases {
            attributes[style.key] = styles.contains(style) ? true : nil
        }
        attributes[.markdownLink] = link
        return attributes
    }
}

extension NSMutableAttributedString {
    /// Sets the font, colour, strikethrough, shading, baseline offset and
    /// underline of every character in `range` from its line's style, its
    /// inline styles and its link. Needed wherever those are set.
    func applyAppearance(in range: NSRange) {
        enumerateAttributes(in: range) { attributes, run, _ in
            var look: [NSAttributedString.Key: Any] = [:]
            if attributes[.sourceLine] != nil {
                look[.font] = SourceStyle.font
                look[.foregroundColor] = UIColor.secondaryLabel
            } else {
                let style = (attributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
                let styles = Set(InlineStyle.allCases.filter { attributes[$0.key] != nil })
                let link = attributes[.markdownLink] as? String
                look[.font] = style.font(for: styles)
                look[.foregroundColor] = link == nil ? UIColor.label : InlineStyle.linkColor
                look[.underlineStyle] = link == nil ? nil : NSUnderlineStyle.single.rawValue
                look[.strikethroughStyle] = styles.contains(.strikethrough) ? NSUnderlineStyle.single.rawValue : nil
                look[.backgroundColor] = styles.contains(.highlight) ? InlineStyle.highlightColor
                    : styles.contains(.code) ? InlineStyle.codeBackground : nil
                look[.baselineOffset] = style.baselineOffset(for: styles)
            }
            for key in [NSAttributedString.Key.font, .foregroundColor, .underlineStyle, .strikethroughStyle,
                        .backgroundColor, .baselineOffset] {
                if let value = look[key] {
                    if !(attributes[key].map { ($0 as AnyObject).isEqual(value) } ?? false) {
                        addAttribute(key, value: value, range: run)
                    }
                } else if attributes[key] != nil {
                    removeAttribute(key, range: run)
                }
            }
        }
    }
}
