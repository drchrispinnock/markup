import Foundation

/// A tag: a value kept up to date from a project's files, written between
/// two HTML comments that name it. Markdown readers show only the value.
/// - A variable, `<!-- MARKUPTAG noofbakers-->2<!-- ENDMARKUPTAG -->`, takes
///   its value from `variables.txt` (or `tags.txt`).
/// - A citation, `<!-- MARKUPBIBTAG R-1 -->[1]<!-- ENDMARKUPBIBTAG -->`, is
///   the number of its entry in `bibliography.txt`.
public struct MarkupTag: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case variable
        case citation
    }

    public var kind: Kind
    public var name: String
    public var value: String
    /// The comment before the value, as written.
    var opening: String
    /// The comment after the value, as written.
    var closing: String

    /// The value shown for a variable that has no value.
    public static let unknownValue = "??"
    /// The value shown for a citation that `bibliography.txt` has no entry
    /// for.
    public static let unknownCitation = "[??]"

    /// A tag written in the usual form.
    public init(name: String, value: String, kind: Kind = .variable) {
        self.kind = kind
        self.name = name
        self.value = value
        switch kind {
        case .variable:
            opening = "<!-- MARKUPTAG \(name)-->"
            closing = "<!-- ENDMARKUPTAG -->"
        case .citation:
            opening = "<!-- MARKUPBIBTAG \(name) -->"
            closing = "<!-- ENDMARKUPBIBTAG -->"
        }
    }

    /// A citation of the bibliography entry `key`, with no value yet.
    public static func citation(_ key: String) -> MarkupTag {
        MarkupTag(name: key, value: unknownCitation, kind: .citation)
    }

    /// The tag as Markdown: its comments exactly as they were read, around
    /// its value.
    public var markdown: String { opening + value + closing }

    /// Whether the value is the one shown when there is none.
    public var isUnknown: Bool {
        value == (kind == .variable ? Self.unknownValue : Self.unknownCitation)
    }

    /// Whether `name` can be a tag's name: letters, digits, `_`, `-` and `.`.
    public static func isValid(name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { nameCharacters.contains($0) }
    }

    private static let nameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))

    private static func pattern(_ word: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: #"(<!--\s*MARKUP"# + word + #"TAG\s+([\p{L}\p{N}_.\-]+)\s*-->)((?:(?!<!--)[^\n])*?)(<!--\s*ENDMARKUP"#
            + word + #"TAG\s*-->)"#)
    }

    private static let patterns: [(Kind, NSRegularExpression)] = [(.variable, pattern("")), (.citation, pattern("BIB"))]

    /// The tags and citations in `text`, in order, with their ranges as
    /// UTF-16 offsets. A value can't hold a newline or a comment.
    public static func tags(in text: String) -> [(range: Range<Int>, tag: MarkupTag)] {
        let string = text as NSString
        var found: [(range: Range<Int>, tag: MarkupTag)] = []
        for (kind, pattern) in patterns {
            for match in pattern.matches(in: text, range: NSRange(location: 0, length: string.length)) {
                var tag = MarkupTag(name: string.substring(with: match.range(at: 2)),
                                    value: string.substring(with: match.range(at: 3)), kind: kind)
                tag.opening = string.substring(with: match.range(at: 1))
                tag.closing = string.substring(with: match.range(at: 4))
                found.append((match.range.location..<NSMaxRange(match.range), tag))
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// This tag with its value from `sources`: a variable's from the
    /// variables, or unknown; a citation's entry number in the bibliography, or unknown.
    /// Without the file it needs, it is unchanged.
    public func updated(from sources: TagSources) -> MarkupTag {
        var tag = self
        switch kind {
        case .variable:
            guard let values = sources.variables else { return self }
            tag.value = values[name] ?? Self.unknownValue
        case .citation:
            guard let bibliography = sources.bibliography else { return self }
            tag.value = bibliography.citation(of: name)
        }
        return tag
    }

    /// `markdown` with every variable's and citation's value, and every
    /// bibliography, set from `sources`, except in code blocks.
    public static func updating(markdown: String, from sources: TagSources) -> String {
        var lines = MarkdownCodec.lines(fromMarkdown: markdown)
        var changed = false
        for index in lines.indices where lines[index].style != .code {
            let text = lines[index].text
            let found = tags(in: text)
            guard !found.isEmpty else { continue }
            var units = Array(text.utf16)
            for (range, tag) in found.reversed() {
                let updated = tag.updated(from: sources)
                guard updated != tag else { continue }
                units.replaceSubrange(range, with: Array(updated.markdown.utf16))
                changed = true
            }
            lines[index].text = String(decoding: units, as: UTF16.self)
        }
        if let bibliography = sources.bibliography {
            for block in Bibliography.blocks(in: lines).reversed() {
                let current = MarkdownCodec.markdown(from: Array(lines[block]))
                let wanted = bibliography.markdown(hanging: sources.hangingBibliography)
                guard Bibliography.normalized(current) != Bibliography.normalized(wanted) else { continue }
                lines.replaceSubrange(block, with: MarkdownCodec.lines(fromMarkdown: wanted))
                changed = true
            }
        }
        return changed ? MarkdownCodec.markdown(from: lines) : markdown
    }
}

/// Where variables and citations get their values: the project's
/// `variables.txt` (or `tags.txt`) and `bibliography.txt`, either of which
/// may be missing.
public struct TagSources: Equatable, Sendable {
    public var variables: [String: String]?
    public var bibliography: Bibliography?
    /// Whether a bibliography is written between Leanpub's
    /// `{begin-hanging-paragraphs}` and `{end-hanging-paragraphs}`.
    public var hangingBibliography: Bool

    public init(variables: [String: String]? = nil, bibliography: Bibliography? = nil, hangingBibliography: Bool = true) {
        self.variables = variables
        self.bibliography = bibliography
        self.hangingBibliography = hangingBibliography
    }

    public var isEmpty: Bool { variables == nil && bibliography == nil }
}

/// A project's `variables.txt`: a line per variable, its name and value
/// separated by `|`. Blank lines and lines starting with `#` are ignored, as
/// are any fields after the second.
public enum VariableFile {
    /// The files read, in order: `variables.txt`, and for now `tags.txt`,
    /// the name variables had when they were called tags.
    public static let names = ["variables.txt", "tags.txt"]

    /// The values of the files' `texts`, in the order of `names`: each
    /// variable's from the first file that has a value for it.
    public static func values(fromFiles texts: [String]) -> [String: String] {
        texts.reversed().reduce(into: [:]) { values, text in values.merge(Self.values(from: text)) { $1 } }
    }

    /// Each variable's value, by name. A line without a value gives none.
    public static func values(from text: String) -> [String: String] {
        var values: [String: String] = [:]
        for (name, rest) in fields(of: text) {
            let value = rest.split(separator: "|", omittingEmptySubsequences: false)[0].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { values[name] = value }
        }
        return values
    }

    /// Each line's name and the rest of the line after the first `|`,
    /// skipping blank lines, lines starting with `#`, lines without a `|`
    /// and names that can't be a variable's.
    static func fields(of text: String) -> [(name: String, rest: String)] {
        text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let bar = trimmed.firstIndex(of: "|") else { return nil }
            let name = trimmed[..<bar].trimmingCharacters(in: .whitespaces)
            guard MarkupTag.isValid(name: name) else { return nil }
            return (name, String(trimmed[trimmed.index(after: bar)...]))
        }
    }
}
