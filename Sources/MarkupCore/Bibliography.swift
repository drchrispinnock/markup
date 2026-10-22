/// A project's `bibliography.txt`: a line per entry, numbered from 1 in
/// order. `SEC|title` starts a section. An entry is just its text, cited by
/// a key made from it (eight hexadecimal digits), or `key|text` to choose
/// the key. Blank lines and lines starting with `#` are ignored.
///
/// Citations (`MarkupTag.citation`) show an entry's number, `[1]`. The
/// bibliography itself is written between `<!-- MARKUPBIBLIOGRAPHY -->` and
/// `<!-- ENDMARKUPBIBLIOGRAPHY -->`, each alone on its line, so it can be
/// written again when the file changes.
public struct Bibliography: Equatable, Sendable {
    public static let fileName = "bibliography.txt"
    public static let start = "<!-- MARKUPBIBLIOGRAPHY -->"
    public static let end = "<!-- ENDMARKUPBIBLIOGRAPHY -->"
    static let sectionKey = "SEC"

    public struct Entry: Equatable, Sendable {
        public var key: String
        /// The entry as written: Markdown.
        public var text: String
        public var number: Int
    }

    public struct Section: Equatable, Sendable {
        /// Nil for entries before the first section.
        public var title: String?
        public var entries: [Entry]
    }

    public var sections: [Section]

    public init(text: String) {
        var sections: [Section] = []
        var number = 0
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let key: String
            let value: String
            if let bar = trimmed.firstIndex(of: "|"), case let name = trimmed[..<bar].trimmingCharacters(in: .whitespaces),
               MarkupTag.isValid(name: name) {
                key = name
                value = trimmed[trimmed.index(after: bar)...].trimmingCharacters(in: .whitespaces)
            } else {
                value = trimmed
                key = Self.key(for: value)
            }
            if key == Self.sectionKey {
                sections.append(Section(title: value, entries: []))
                continue
            }
            guard !value.isEmpty else { continue }
            number += 1
            if sections.isEmpty { sections.append(Section(title: nil, entries: [])) }
            sections[sections.count - 1].entries.append(Entry(key: key, text: value, number: number))
        }
        self.sections = sections
    }

    public var entries: [Entry] { sections.flatMap(\.entries) }

    /// The key of an entry written without one: its text's hash.
    public static func key(for text: String) -> String {
        HeadingIDScheme.hash(text)
    }

    /// The entry for `key`: the first, if more than one has it.
    public func entry(for key: String) -> Entry? {
        entries.first { $0.key == key }
    }

    /// What a citation of `key` shows: `[n]`, or `[??]` with no such entry.
    public func citation(of key: String) -> String {
        entry(for: key).map { "[\($0.number)]" } ?? MarkupTag.unknownCitation
    }

    /// The bibliography as Markdown, between its markers: each section's
    /// title in bold, then its entries, `[n] text`, a paragraph each. With
    /// `hanging`, inside Leanpub's hanging paragraphs.
    public func markdown(hanging: Bool) -> String {
        var paragraphs: [String] = []
        if hanging { paragraphs.append("{begin-hanging-paragraphs}") }
        for section in sections {
            if let title = section.title { paragraphs.append("**\(title)**") }
            paragraphs += section.entries.map { "[\($0.number)] \($0.text)" }
        }
        if hanging { paragraphs.append("{end-hanging-paragraphs}") }
        return ([Self.start] + [paragraphs.joined(separator: "\n\n")] + [Self.end]).joined(separator: "\n")
    }

    /// The ranges of `lines` that are bibliographies: each from a line that
    /// is just the start marker to the next that is just the end marker,
    /// markers included, outside code.
    static func blocks(in lines: [Line]) -> [Range<Int>] {
        var blocks: [Range<Int>] = []
        var start: Int?
        for (index, line) in lines.enumerated() where line.style != .code && line.list == nil {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            if text == Self.start {
                start = index
            } else if text == Self.end, let first = start {
                blocks.append(first..<index + 1)
                start = nil
            }
        }
        return blocks
    }

    /// `markdown` as the inline writer would write it back, so a
    /// bibliography read from a file can be compared with one made anew.
    public static func normalized(_ markdown: String) -> String {
        MarkdownCodec.markdown(from: MarkdownCodec.lines(fromMarkdown: markdown).map { line in
            guard line.style != .code, line.style != .table else { return line }
            var line = line
            line.text = InlineMarkdown.markdown(for: InlineMarkdown.spans(in: line.text))
            return line
        })
    }
}
