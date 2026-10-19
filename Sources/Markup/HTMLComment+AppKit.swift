import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// The text of an HTML comment, exactly as written, on the attachment
    /// character that stands for it in the formatted view, which shows
    /// nothing. Saving and copying write it back unchanged.
    static let markdownComment = NSAttributedString.Key("MarkupComment")
}

extension HTMLComment {
    /// The hidden attachment character for the comment `markdown`, with the
    /// line's `attributes`.
    @MainActor
    static func attachmentString(markdown: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = HiddenAttachmentCell()
        var attributes = attributes
        attributes[.attachment] = attachment
        attributes[.markdownComment] = markdown
        return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
    }

    /// The paragraph style of a line holding only comments, which takes up
    /// no space.
    @MainActor static let hiddenLineStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 0.01
        style.maximumLineHeight = 0.01
        return style
    }()
}

/// Draws nothing and takes no space.
final class HiddenAttachmentCell: NSTextAttachmentCell {
    nonisolated override func cellSize() -> NSSize { .zero }
    nonisolated override func cellBaselineOffset() -> NSPoint { .zero }
    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int,
                                   layoutManager: NSLayoutManager) {}
}
