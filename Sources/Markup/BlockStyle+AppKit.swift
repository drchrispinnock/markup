import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// The `BlockStyle` raw value of the line a character belongs to. Every
    /// character of a line, including its newline, carries the same value.
    static let blockStyle = NSAttributedString.Key("MarkupBlockStyle")
}

extension BlockStyle {
    var font: NSFont {
        switch self {
        case .heading: .systemFont(ofSize: 28, weight: .bold)
        case .subheading: .systemFont(ofSize: 22, weight: .bold)
        case .subsubheading: .systemFont(ofSize: 18, weight: .semibold)
        case .paragraph: .systemFont(ofSize: 15)
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
