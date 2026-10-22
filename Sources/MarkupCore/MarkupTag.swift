import Foundation

/// A tag: a value kept up to date from a project's `tags.txt`, written
/// between two HTML comments that name it,
/// `<!-- MARKUPTAG noofbakers-->2<!-- ENDMARKUPTAG -->`. Markdown readers
/// show only the value.
public struct MarkupTag: Hashable, Sendable {
    public var name: String
    public var value: String
    /// The comment before the value, as written.
    var opening: String
    /// The comment after the value, as written.
    var closing: String

    /// The value shown for a tag that `tags.txt` has no value for.
    public static let unknownValue = "??"

    /// A tag written in the usual form.
    public init(name: String, value: String) {
        self.name = name
        self.value = value
        opening = "<!-- MARKUPTAG \(name)-->"
        closing = "<!-- ENDMARKUPTAG -->"
    }

    /// The tag as Markdown: its comments exactly as they were read, around
    /// its value.
    public var markdown: String { opening + value + closing }

    /// Whether `name` can be a tag's name: letters, digits, `_`, `-` and `.`.
    public static func isValid(name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { nameCharacters.contains($0) }
    }

    private static let nameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))

    private static let pattern = try! NSRegularExpression(
        pattern: #"(<!--\s*MARKUPTAG\s+([\p{L}\p{N}_.\-]+)\s*-->)((?:(?!<!--)[^\n])*?)(<!--\s*ENDMARKUPTAG\s*-->)"#)

    /// The tags in `text`, in order, with their ranges as UTF-16 offsets. A
    /// value can't hold a newline or a comment.
    public static func tags(in text: String) -> [(range: Range<Int>, tag: MarkupTag)] {
        let string = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: string.length)).map { match in
            var tag = MarkupTag(name: string.substring(with: match.range(at: 2)), value: string.substring(with: match.range(at: 3)))
            tag.opening = string.substring(with: match.range(at: 1))
            tag.closing = string.substring(with: match.range(at: 4))
            return (match.range.location..<NSMaxRange(match.range), tag)
        }
    }

    /// This tag with the value `values` has for it, or `unknownValue`.
    public func updated(from values: [String: String]) -> MarkupTag {
        var tag = self
        tag.value = values[name] ?? Self.unknownValue
        return tag
    }

    /// `markdown` with every tag's value set from `values`, except in code
    /// blocks.
    public static func updating(markdown: String, from values: [String: String]) -> String {
        var lines = MarkdownCodec.lines(fromMarkdown: markdown)
        var changed = false
        for index in lines.indices where lines[index].style != .code {
            let text = lines[index].text
            let found = tags(in: text)
            guard !found.isEmpty else { continue }
            var units = Array(text.utf16)
            for (range, tag) in found.reversed() {
                let updated = tag.updated(from: values)
                guard updated != tag else { continue }
                units.replaceSubrange(range, with: Array(updated.markdown.utf16))
                changed = true
            }
            lines[index].text = String(decoding: units, as: UTF16.self)
        }
        return changed ? MarkdownCodec.markdown(from: lines) : markdown
    }
}

/// A project's `tags.txt`: a line per tag, its name and value separated by
/// `|`. Blank lines and lines starting with `#` are ignored, as are any
/// fields after the second.
public enum TagFile {
    public static let name = "tags.txt"

    /// Each tag's value, by name. A line without a value gives none.
    public static func values(from text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let fields = trimmed.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, MarkupTag.isValid(name: fields[0]), !fields[1].isEmpty else { continue }
            values[fields[0]] = fields[1]
        }
        return values
    }
}
