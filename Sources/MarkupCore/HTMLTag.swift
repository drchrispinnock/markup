import Foundation

/// The few HTML tags the formatted view shows for what they are: `<br>`,
/// `<img>`, and `<p>` and `</p>`. Others stay text. Names and attributes are
/// read as HTML has them, in any case; a tag is kept exactly as written.
public struct HTMLTag: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case lineBreak
        case image
        case paragraphStart
        case paragraphEnd
    }

    public var kind: Kind
    /// The attributes, by lowercased name. One without a value has "".
    public var attributes: [String: String]

    public init(kind: Kind, attributes: [String: String] = [:]) {
        self.kind = kind
        self.attributes = attributes
    }

    /// An `<img>`'s image: its `src` and `alt`. Nil for other tags.
    public var image: MarkdownImage? {
        guard kind == .image, let src = attributes["src"], !src.isEmpty else { return nil }
        return MarkdownImage(alt: attributes["alt"] ?? "", path: src)
    }

    /// A tag that holds only `<p>` or `</p>` is hidden, as a comment is.
    public var isParagraph: Bool { kind == .paragraphStart || kind == .paragraphEnd }

    private static let attribute = #"[A-Za-z_:][-A-Za-z0-9_:.]*(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?"#
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<!\\)<(/?)(br|img|p)((?:\s+"# + attribute + #")*)\s*(/?)>"#, options: .caseInsensitive)
    private static let attributePattern = try! NSRegularExpression(
        pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#)

    /// The tags in `text`, in order, with their ranges as UTF-16 offsets. A
    /// tag after a backslash is text, as is an `<img>` without a `src`, a
    /// closing tag other than `</p>`, one with attributes, or one that also
    /// closes itself.
    public static func tags(in text: String) -> [(range: Range<Int>, tag: HTMLTag)] {
        let string = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: string.length)).compactMap { match in
            let closing = match.range(at: 1).length > 0
            let name = string.substring(with: match.range(at: 2)).lowercased()
            let attributeText = string.substring(with: match.range(at: 3))
            if closing, name != "p" || !attributeText.isEmpty || match.range(at: 4).length > 0 { return nil }
            let kind: Kind = switch name {
            case "br": .lineBreak
            case "img": .image
            default: closing ? .paragraphEnd : .paragraphStart
            }
            let tag = HTMLTag(kind: kind, attributes: attributes(in: attributeText))
            if kind == .image, tag.image == nil { return nil }
            return (match.range.location..<NSMaxRange(match.range), tag)
        }
    }

    private static func attributes(in text: String) -> [String: String] {
        let string = text as NSString
        var attributes: [String: String] = [:]
        for match in attributePattern.matches(in: text, range: NSRange(location: 0, length: string.length)) {
            let name = string.substring(with: match.range(at: 1)).lowercased()
            let value = (2...4).map { match.range(at: $0) }.first { $0.location != NSNotFound }.map(string.substring(with:))
            // As in HTML, the first of an attribute written twice counts.
            if attributes[name] == nil { attributes[name] = value.map(decodingEntities) ?? "" }
        }
        return attributes
    }

    /// `value` with the character references a path or alt text is likely
    /// to hold decoded.
    private static func decodingEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        return [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]
            .reduce(value) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

extension MarkdownImage {
    /// The image an image's text holds, as written: `![alt](path)` or
    /// `<img src="path" alt="alt">`.
    public static func image(written text: String) -> MarkdownImage? {
        images(in: text).first?.image ?? HTMLTag.tags(in: text).first?.tag.image
    }
}
