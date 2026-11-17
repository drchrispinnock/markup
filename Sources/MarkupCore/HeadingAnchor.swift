import Foundation

/// A heading's ID, which links refer to as `[text](#id)`, and the other
/// attributes on its line, such as Leanpub's `sample: true`. Markua takes
/// attributes only from one line directly above a heading, so they share
/// it: `{id: x, sample: true}`. It is written in one of four forms
/// (`Form`). One already in a file is kept as it was written, unless it is
/// changed.
public struct HeadingAnchor: Hashable, Sendable {
    public enum Form: String, CaseIterable, Sendable {
        /// `{id: x}` on the line above the heading, as Markua has it.
        case idAttribute
        /// `{#id: x}` on the line above the heading, which Markua doesn't
        /// accept (`#id` isn't a key), but Markup once wrote.
        case idLine
        /// `{#x}` on the line above the heading.
        case braceLine
        /// `{#x}` at the end of the heading, as Pandoc writes it. Markua
        /// ignores it.
        case attribute
    }

    /// The ID, or empty for a line of other attributes alone, such as
    /// `{sample: true}`.
    public var id: String
    public var form: Form
    /// The line's attributes besides the ID, each as written
    /// (`sample: true`), in order.
    public var others: [String]
    /// The anchor as read from the file: the line above, or for `attribute`
    /// the `{#x}` at the end. Written back as it was while the ID and other
    /// attributes are the same.
    public var written: String?

    public init(id: String, form: Form, others: [String] = [], written: String? = nil) {
        self.id = id
        self.form = form
        self.others = others
        self.written = written
    }

    /// Whether it has an ID, not just other attributes.
    public var hasID: Bool { !id.isEmpty }

    /// Its Markdown: the line above the heading, or the `{#x}` to end it.
    /// With other attributes, the ID is written `id: x` among them, as the
    /// Markua spec prefers.
    public var markdown: String {
        if let written, let read = Self.anchor(inLine: written) ?? Self.brace(written, form: .attribute),
           read.id == id, read.others == others { return written }
        guard others.isEmpty else { return "{" + ((hasID ? ["id: \(id)"] : []) + others).joined(separator: ", ") + "}" }
        switch form {
        case .idAttribute: return "{id: \(id)}"
        case .idLine: return "{#id: \(id)}"
        case .braceLine, .attribute: return "{#\(id)}"
        }
    }

    /// Whether it has `sample: true`, which Leanpub reads as putting the
    /// heading's section in the book's sample. Setting it false takes the
    /// `sample` attribute off.
    public var isSample: Bool {
        get { others.contains { Self.key(of: $0) == "sample" && Self.value(of: $0) == "true" } }
        set {
            others.removeAll { Self.key(of: $0) == "sample" }
            if newValue { others.append("sample: true") }
            written = nil
        }
    }

    /// This anchor with `other`'s ID, if it has one, and its other
    /// attributes, which replace any with the same keys.
    public func adding(_ other: HeadingAnchor) -> HeadingAnchor {
        let keys = Set(other.others.compactMap(Self.key(of:)))
        return HeadingAnchor(id: other.hasID ? other.id : id, form: other.hasID ? other.form : form,
                             others: others.filter { !keys.contains(Self.key(of: $0) ?? "") } + other.others)
    }

    /// Whether `id` can be written in every form: it is not empty, and has
    /// no spaces, braces or commas.
    public static func isValid(id: some StringProtocol) -> Bool {
        !id.isEmpty && !id.contains { $0.isWhitespace || $0 == "{" || $0 == "}" || $0 == "," }
    }

    /// Whether Markua accepts `id`: an ASCII letter, then ASCII letters,
    /// digits, `-` and `_`. Leanpub ignores any other ID, and the links to
    /// it go nowhere.
    public static func isMarkuaID(_ id: some StringProtocol) -> Bool {
        guard let first = id.first, HeadingIDScheme.isASCIILetter(first) else { return false }
        return id.allSatisfy { HeadingIDScheme.isASCIILetterOrDigit($0) || $0 == "-" || $0 == "_" }
    }

    /// An ID Markua accepts for `id`, unlike any in `taken`: `id` itself if
    /// Markua accepts it, or else made so as new IDs are, with `ID` first
    /// if it doesn't start with a letter.
    public static func markuaID(for id: String, taken: Set<String>) -> String {
        guard !isMarkuaID(id) else { return id }
        let ascii = id.applyingTransform(.stripDiacritics, reverse: false) ?? id
        let base = HeadingIDScheme.startingWithALetter(String(ascii.map {
            HeadingIDScheme.isASCIILetterOrDigit($0) || $0 == "-" || $0 == "_" ? $0 : "_"
        }))
        var candidate = base
        var attempt = 1
        while taken.contains(candidate) {
            attempt += 1
            candidate = "\(base)_\(attempt)"
        }
        return candidate
    }

    /// The anchor that `line`, a line on its own, would be above a heading:
    /// an attribute list with an ID (`{id: x}`, `{#x}` or `{#id: x}`, the
    /// spaces optional), other attributes (`key: value`), or both.
    public init?(line: some StringProtocol) {
        guard let anchor = Self.anchor(inLine: String(line)) else { return nil }
        self = anchor
    }

    private static func anchor(inLine text: String) -> HeadingAnchor? {
        guard text.hasPrefix("{"), text.hasSuffix("}"), text.count >= 3,
              let items = items(in: text.dropFirst().dropLast()) else { return nil }
        var id: String?
        var form = Form.idAttribute
        var others: [String] = []
        for item in items {
            let found: (String, Form)?
            if item.hasPrefix("#id:") {
                found = (String(item.dropFirst(4).drop(while: { $0 == " " })), .idLine)
            } else if item.hasPrefix("#") {
                found = (String(item.dropFirst()), .braceLine)
            } else if key(of: item) == "id" {
                found = (value(of: item) ?? "", .idAttribute)
            } else if key(of: item) != nil {
                others.append(item)
                found = nil
            } else {
                return nil
            }
            if let (value, itemForm) = found {
                guard id == nil, isValid(id: value) else { return nil }
                id = value
                form = itemForm
            }
        }
        guard id != nil || !others.isEmpty else { return nil }
        return HeadingAnchor(id: id ?? "", form: form, others: others, written: text)
    }

    /// `text` as `{#x}` alone, which for `attribute` ends a heading.
    private static func brace(_ text: String, form: Form) -> HeadingAnchor? {
        guard text.hasPrefix("{#"), text.hasSuffix("}"), text.count >= 3 else { return nil }
        let inside = text.dropFirst(2).dropLast()
        guard !inside.hasPrefix("id:"), isValid(id: inside) else { return nil }
        return HeadingAnchor(id: String(inside), form: form, written: text)
    }

    /// The comma-separated items of an attribute list, trimmed, with commas
    /// inside quotes kept; nil if a quote isn't closed or an item is empty.
    private static func items(in text: Substring) -> [String]? {
        var items: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped {
                escaped = false
            } else if character == "\\", quote != nil {
                escaped = true
            } else if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "," {
                items.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(character)
        }
        items.append(current.trimmingCharacters(in: .whitespaces))
        guard quote == nil, !items.contains(where: \.isEmpty) else { return nil }
        return items
    }

    /// The key of `item`, `key: value`, if it has one Markua accepts:
    /// lowercase letters, `-` and `_`.
    private static func key(of item: String) -> String? {
        guard let colon = item.firstIndex(of: ":") else { return nil }
        let key = item[..<colon]
        guard !key.isEmpty, key.allSatisfy({ ($0.isASCII && $0.isLowercase) || $0 == "-" || $0 == "_" }) else { return nil }
        return String(key)
    }

    /// The value of `item`, `key: value`, without spaces around it.
    private static func value(of item: String) -> String? {
        item.firstIndex(of: ":").map { item[item.index(after: $0)...].trimmingCharacters(in: .whitespaces) }
    }

    /// The anchor that ends a heading's text, `{#x}` after a space (or as
    /// the whole text), and the text before it.
    public static func trailing(in text: String) -> (text: String, anchor: HeadingAnchor)? {
        let suffix = trailingWord(of: text)
        guard let anchor = brace(String(suffix), form: .attribute) else { return nil }
        return (String(text.dropLast(suffix.count).dropLast(suffix.count < text.count ? 1 : 0)), anchor)
    }

    /// Whether the end of a heading's text, as text, would read back as an
    /// anchor, and so needs escaping as `\{#x}`. A `{#x}` already escaped
    /// needs another backslash, so that reading takes one off.
    public static func trailingNeedsEscape(_ text: String) -> Bool {
        brace(String(trailingWord(of: text).drop(while: { $0 == "\\" })), form: .attribute) != nil
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
