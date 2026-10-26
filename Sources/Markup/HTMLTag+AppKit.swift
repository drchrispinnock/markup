import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// An HTML tag (`HTMLTag`) other than an image, exactly as written, on
    /// the character that stands for it in the formatted view. Saving and
    /// copying write it back unchanged. An `<img>` carries `.markdownImage`
    /// instead, as an image written in Markdown does.
    static let markdownHTML = NSAttributedString.Key("MarkupHTML")
}

extension HTMLTag {
    /// The character that shows the tag `markdown`, with the line's
    /// `attributes`:
    /// - `<br>` in the middle of a line is a line separator (U+2028), which
    ///   breaks the line where it is without ending it. At the end of a line,
    ///   where the line ends anyway, it is hidden.
    /// - `<img>` is its image, as `![alt](path)` would be.
    /// - `<p>` and `</p>` are hidden, as a comment is.
    @MainActor
    func attachmentString(markdown: String, attributes: [NSAttributedString.Key: Any], folders: [URL],
                          endsLine: Bool) -> NSAttributedString {
        if let image {
            return image.attachmentString(markdown: markdown, attributes: attributes, folders: folders)
        }
        if kind == .lineBreak, !endsLine {
            var attributes = attributes
            attributes[.markdownHTML] = markdown
            return NSAttributedString(string: "\u{2028}", attributes: attributes)
        }
        let hidden = NSMutableAttributedString(attributedString: HTMLComment.attachmentString(markdown: markdown,
                                                                                               attributes: attributes))
        hidden.removeAttribute(.markdownComment, range: NSRange(location: 0, length: 1))
        hidden.addAttribute(.markdownHTML, value: markdown, range: NSRange(location: 0, length: 1))
        return hidden
    }
}
