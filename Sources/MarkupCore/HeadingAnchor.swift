/// A heading's ID, which links refer to as `[text](#id)`. It is written in
/// one of three forms (`Form`). One already in a file is kept as it was
/// written, unless its ID is changed.
public struct HeadingAnchor: Hashable, Sendable {
    public enum Form: String, CaseIterable, Sendable {
        /// `{#id: x}` on the line above the heading.
        case idLine
        /// `{#x}` on the line above the heading.
        case braceLine
        /// `{#x}` at the end of the heading, as Pandoc writes it.
        case attribute
    }

    public var id: String
    public var form: Form
    /// The anchor as read from the file: the line above, or for `attribute`
    /// the `{#x}` at the end. Written back as it was while the ID is the
    /// same.
    public var written: String?

    public init(id: String, form: Form, written: String? = nil) {
        self.id = id
        self.form = form
        self.written = written
    }

    /// Its Markdown: the line above the heading, or the `{#x}` to end it.
    public var markdown: String {
        if let written, Self.anchor(in: written, form: form)?.id == id { return written }
        switch form {
        case .idLine: return "{#id: \(id)}"
        case .braceLine, .attribute: return "{#\(id)}"
        }
    }

    /// Whether `id` can be written in every form: it is not empty, and has
    /// no spaces or braces.
    public static func isValid(id: some StringProtocol) -> Bool {
        !id.isEmpty && !id.contains { $0.isWhitespace || $0 == "{" || $0 == "}" }
    }

    /// The anchor that `line`, a line on its own, would be above a heading:
    /// `{#id: x}` (the spaces are optional) or `{#x}`.
    public init?(line: some StringProtocol) {
        guard let anchor = Self.anchor(in: String(line), form: .idLine) ?? Self.anchor(in: String(line), form: .braceLine)
        else { return nil }
        self = anchor
    }

    /// `text` read as `form`, which for `attribute` is the `{#x}` alone.
    private static func anchor(in text: String, form: Form) -> HeadingAnchor? {
        guard text.hasPrefix("{#"), text.hasSuffix("}"), text.count >= 3 else { return nil }
        let inside = text.dropFirst(2).dropLast()
        let isIDLine = inside.hasPrefix("id:")
        switch form {
        case .idLine:
            guard isIDLine else { return nil }
            let id = inside.dropFirst(3).drop(while: { $0 == " " })
            let trimmed = id.prefix(while: { $0 != " " })
            guard isValid(id: trimmed), id.dropFirst(trimmed.count).allSatisfy({ $0 == " " }) else { return nil }
            return HeadingAnchor(id: String(trimmed), form: .idLine, written: text)
        case .braceLine, .attribute:
            guard !isIDLine, isValid(id: inside) else { return nil }
            return HeadingAnchor(id: String(inside), form: form, written: text)
        }
    }

    /// The anchor that ends a heading's text, `{#x}` after a space (or as
    /// the whole text), and the text before it.
    public static func trailing(in text: String) -> (text: String, anchor: HeadingAnchor)? {
        let suffix = trailingWord(of: text)
        guard let anchor = anchor(in: String(suffix), form: .attribute) else { return nil }
        return (String(text.dropLast(suffix.count).dropLast(suffix.count < text.count ? 1 : 0)), anchor)
    }

    /// Whether the end of a heading's text, as text, would read back as an
    /// anchor, and so needs escaping as `\{#x}`. A `{#x}` already escaped
    /// needs another backslash, so that reading takes one off.
    public static func trailingNeedsEscape(_ text: String) -> Bool {
        anchor(in: String(trailingWord(of: text).drop(while: { $0 == "\\" })), form: .attribute) != nil
    }

    /// `text` with a backslash before its trailing `{#x}`.
    public static func escapingTrailing(_ text: String) -> String {
        let suffix = trailingWord(of: text)
        return String(text.dropLast(suffix.count)) + "\\" + suffix
    }

    /// `text` with one backslash taken off an escaped trailing `{#x}`.
    public static func unescapingTrailing(_ text: String) -> String {
        let suffix = trailingWord(of: text)
        guard suffix.first == "\\", trailingNeedsEscape(text) else { return text }
        return String(text.dropLast(suffix.count)) + suffix.dropFirst()
    }

    /// The text after the last space.
    private static func trailingWord(of text: String) -> Substring {
        guard let space = text.lastIndex(of: " ") else { return Substring(text) }
        return text[text.index(after: space)...]
    }
}
