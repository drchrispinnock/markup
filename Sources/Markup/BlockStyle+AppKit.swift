import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// The `BlockStyle` raw value of the line a character belongs to. Every
    /// character of a line, including its newline, carries the same value.
    static let blockStyle = NSAttributedString.Key("MarkupBlockStyle")
    /// The `CodeFence` of a code block, on every character of the block,
    /// when it isn't plain "```". A change of fence between two code lines
    /// starts a new block.
    static let codeFence = NSAttributedString.Key("MarkupCodeFence")
    /// True on every character of a table's header cells, which are bold.
    static let tableHeader = NSAttributedString.Key("MarkupTableHeader")
    /// A heading's ID (`HeadingAnchor`), on every character of the line. It
    /// isn't shown, and only a heading writes it.
    static let headingAnchor = NSAttributedString.Key("MarkupHeadingAnchor")
}

extension BlockStyle {
    var font: NSFont {
        switch self {
        case .heading: .systemFont(ofSize: 28, weight: .bold)
        case .subheading: .systemFont(ofSize: 22, weight: .bold)
        case .subsubheading: .systemFont(ofSize: 18, weight: .semibold)
        case .paragraph: .systemFont(ofSize: 15)
        case .code: .monospacedSystemFont(ofSize: 13.5, weight: .regular)
        case .table: .systemFont(ofSize: 15)
        }
    }

    var attributes: [NSAttributedString.Key: Any] {
        [
            .blockStyle: rawValue,
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: NSParagraphStyle.default,
        ]
    }
}

extension NSAttributedString {
    func blockStyle(at location: Int) -> BlockStyle {
        (attribute(.blockStyle, at: location, effectiveRange: nil) as? Int).flatMap(BlockStyle.init) ?? .paragraph
    }
}
