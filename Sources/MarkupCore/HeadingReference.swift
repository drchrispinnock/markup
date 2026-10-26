import Foundation

/// A link's destination when it goes to a heading by its ID: `#id` for a
/// heading in the same file (or, as Leanpub has it, anywhere in the book),
/// or `path#id` for one in another file.
public struct HeadingReference: Hashable, Sendable {
    /// The other file's path as written, percent-decoded, or nil for `#id`.
    public var path: String?
    public var id: String

    public init(path: String? = nil, id: String) {
        self.path = path
        self.id = id
    }

    /// The reference `destination` makes, if it has an ID after a `#`. A
    /// web address or any other URL with a scheme (`https:`, `mailto:`)
    /// isn't one.
    public init?(destination: String) {
        guard let hash = destination.firstIndex(of: "#") else { return nil }
        let path = String(destination[..<hash])
        let id = String(destination[destination.index(after: hash)...])
        guard HeadingAnchor.isValid(id: id), !path.contains(":") else { return nil }
        self.path = path.isEmpty ? nil : path.removingPercentEncoding ?? path
        self.id = id
    }

    /// A link to a heading found in a file's Markdown.
    public struct Occurrence: Equatable, Sendable {
        public var reference: HeadingReference
        /// The link's text, without Markdown.
        public var text: String
    }

    /// Every link to a heading in `markdown`, in order. Code blocks and
    /// front matter have none.
    public static func occurrences(inMarkdown markdown: String) -> [Occurrence] {
        var occurrences: [Occurrence] = []
        for line in MarkdownCodec.lines(fromMarkdown: markdown) where line.style != .code && line.style != .frontMatter {
            // A link is the run of spans with its destination, styled or not.
            var previous: String?
            for span in InlineMarkdown.spans(in: line.text) {
                defer { previous = span.link }
                guard let link = span.link, let reference = HeadingReference(destination: link) else { continue }
                if link == previous, let last = occurrences.indices.last {
                    occurrences[last].text += span.text
                } else {
                    occurrences.append(Occurrence(reference: reference, text: span.text))
                }
            }
        }
        return occurrences
    }
}

extension MarkdownCodec {
    /// The IDs of the headings in `markdown`.
    public static func headingIDs(inMarkdown markdown: String) -> Set<String> {
        Set(lines(fromMarkdown: markdown).compactMap { $0.isTitledHeading ? $0.anchor?.id : nil })
    }
}
