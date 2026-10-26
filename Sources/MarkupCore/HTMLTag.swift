import Foundation

/// The few HTML tags the formatted view shows for what they are: `<br>`,
/// `<img>`, `<p>` and `</p>`, and the formatting tags `HTMLFormat` names,
/// such as `<strong>` and `</strong>`. Others stay text. Names and
/// attributes are read as HTML has them, in any case; a tag is kept exactly
/// as written.
public struct HTMLTag: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case lineBreak
        case image
        case paragraphStart
        case paragraphEnd
        /// An opening formatting tag, such as `<strong>` or `<h4>`.
        case formatStart(HTMLFormat)
        /// A closing one, such as `</strong>`.
        case formatEnd(HTMLFormat)
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
        pattern: #"(?<!\\)<(/?)(br|img|p|strong|b|em|i|h[1-6])((?:\s+"# + attribute + #")*)\s*(/?)>"#,
        options: .caseInsensitive)
    private static let attributePattern = try! NSRegularExpression(
        pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#)

    /// The tags in `text`, in order, with their ranges as UTF-16 offsets. A
    /// tag after a backslash is text, as is an `<img>` without a `src`, a
    /// closing `</br>` or `</img>`, a closing tag with attributes or one that
    /// also closes itself, and a formatting tag that closes itself.
    public static func tags(in text: String) -> [(range: Range<Int>, tag: HTMLTag)] {
        let string = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: string.length)).compactMap { match in
            let closing = match.range(at: 1).length > 0
            let name = string.substring(with: match.range(at: 2)).lowercased()
            let attributeText = string.substring(with: match.range(at: 3))
            let selfClosing = match.range(at: 4).length > 0
            if closing, name == "br" || name == "img" || !attributeText.isEmpty || selfClosing { return nil }
            let format = HTMLFormat(tagName: name)
            if format != nil, selfClosing { return nil }
            let kind: Kind = switch name {
            case "br": .lineBreak
            case "img": .image
            case "p": closing ? .paragraphEnd : .paragraphStart
            default: closing ? .formatEnd(format!) : .formatStart(format!)
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

/// What an HTML formatting tag does to the text up to its closing tag:
/// `<strong>` and `<b>` bold it, `<em>` and `<i>` italicise it, and `<h1>`
/// to `<h6>` make it a heading of that level.
public enum HTMLFormat: Hashable, Sendable {
    case bold
    case italic
    case heading(Int)

    init?(tagName name: String) {
        switch name {
        case "strong", "b": self = .bold
        case "em", "i": self = .italic
        default:
            guard name.count == 2, name.first == "h", let level = Int(name.dropFirst()), (1...6).contains(level) else { return nil }
            self = .heading(level)
        }
    }

    /// The formats each part of a line gets from the formatting tags in it,
    /// given `tags`, the line's tags with their places, in order. A format
    /// applies from its opening tag to the next closing one for it, and an
    /// opening tag without one does nothing. The ranges hold no tags.
    public static func ranges(in length: Int, tags: [(range: Range<Int>, tag: HTMLTag)])
        -> [(range: Range<Int>, formats: Set<HTMLFormat>)] {
        var pairs: [(range: Range<Int>, format: HTMLFormat)] = []
        var open: [(end: Int, format: HTMLFormat)] = []
        for (range, tag) in tags {
            switch tag.kind {
            case .formatStart(let format):
                open.append((range.upperBound, format))
            case .formatEnd(let format):
                if let index = open.lastIndex(where: { $0.format == format }) {
                    pairs.append((open[index].end..<range.lowerBound, format))
                    open.remove(at: index)
                }
            default:
                break
            }
        }
        // Each stretch between places where formats start or end, less the
        // tags.
        let tagRanges = tags.map(\.range)
        let edges = Set(pairs.flatMap { [$0.range.lowerBound, $0.range.upperBound] } + tagRanges.flatMap { [$0.lowerBound, $0.upperBound] })
            .filter { $0 >= 0 && $0 <= length }.sorted()
        var result: [(range: Range<Int>, formats: Set<HTMLFormat>)] = []
        for (start, end) in zip(edges, edges.dropFirst()) where start < end {
            guard !tagRanges.contains(where: { $0.lowerBound <= start && end <= $0.upperBound }) else { continue }
            let formats = Set(pairs.filter { $0.range.lowerBound <= start && end <= $0.range.upperBound }.map(\.format))
            if !formats.isEmpty { result.append((start..<end, formats)) }
        }
        return result
    }
}

extension MarkdownImage {
    /// The image an image's text holds, as written: `![alt](path)` or
    /// `<img src="path" alt="alt">`.
    public static func image(written text: String) -> MarkdownImage? {
        images(in: text).first?.image ?? HTMLTag.tags(in: text).first?.tag.image
    }
}
