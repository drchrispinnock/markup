import Foundation

/// How a heading without an ID is given one. Every scheme avoids the IDs
/// already taken, which across a project is every heading's in every file,
/// and makes an ID Markua accepts (`HeadingAnchor.isMarkuaID`): a letter,
/// then letters, digits, `-` and `_`, all ASCII. One that wouldn't start
/// with a letter starts with `ID`.
public enum HeadingIDScheme: String, CaseIterable, Sendable {
    /// The file's name, the heading's level and its first word (up to ten
    /// characters): `ID170_dapps_2_Setting` for "## Setting up my Dapp" in
    /// `170_dapps.md`. A clash adds `_2`, `_3`...
    case fileLevelWord
    /// `ID` and eight hexadecimal digits, from a hash of the file's name,
    /// the level and the heading.
    case hash
    /// The heading in lower case, words joined by hyphens, as GitHub makes
    /// them: `setting-up-my-dapp`. A clash adds `-1`, `-2`...
    case slug

    /// A new ID for a heading of `level` with `text` (its Markdown), in the
    /// file named `fileName` (nil for one never saved), that isn't in
    /// `taken`.
    public func makeID(text: String, level: Int, fileName: String?, taken: Set<String>) -> String {
        let stem = Self.stem(of: fileName ?? "Untitled")
        let words = Self.words(in: Self.plainText(text))
        switch self {
        case .fileLevelWord:
            let base = Self.startingWithALetter(
                ([stem, String(level)] + words.prefix(1).map { String($0.prefix(10)) }).joined(separator: "_"))
            return Self.unique(base, taken: taken) { "\(base)_\($0)" }
        case .hash:
            return Self.unique("ID" + Self.hash("\(stem)\n\(level)\n\(text)"), taken: taken) {
                "ID" + Self.hash("\(stem)\n\(level)\n\(text)\n\($0)")
            }
        case .slug:
            let base = Self.startingWithALetter(words.isEmpty ? "section" : words.map { $0.lowercased() }.joined(separator: "-"))
            return Self.unique(base, taken: taken) { "\(base)-\($0 - 1)" }
        }
    }

    /// `id`, with `ID` before it unless it starts with a letter.
    static func startingWithALetter(_ id: String) -> String {
        id.first.map(Self.isASCIILetter) == true ? id : "ID" + id
    }

    static func isASCIILetter(_ character: Character) -> Bool {
        character.isASCII && character.isLetter
    }

    static func isASCIILetterOrDigit(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    /// `base`, or else the first of `variant(2)`, `variant(3)`... not taken.
    private static func unique(_ base: String, taken: Set<String>, variant: (Int) -> String) -> String {
        var id = base
        var attempt = 1
        while taken.contains(id) {
            attempt += 1
            id = variant(attempt)
        }
        return id
    }

    /// The file's name without its extension, without accents, and with
    /// anything but ASCII letters, digits, `-` and `_` made `_`.
    private static func stem(of fileName: String) -> String {
        let name = ascii(fileName.lastIndex(of: ".").map { String(fileName[..<$0]) } ?? fileName)
        let stem = String(name.map { isASCIILetterOrDigit($0) || $0 == "-" || $0 == "_" ? $0 : "_" })
        return stem.isEmpty ? "Untitled" : stem
    }

    /// The heading's words: its runs of ASCII letters and digits, once
    /// accents are taken off.
    private static func words(in text: String) -> [Substring] {
        ascii(text).split { !isASCIILetterOrDigit($0) }
    }

    /// `text` without accents: `é` is `e`.
    private static func ascii(_ text: String) -> String {
        text.applyingTransform(.stripDiacritics, reverse: false) ?? text
    }

    /// The heading's text without its Markdown: no emphasis delimiters,
    /// and a link's text without its destination.
    private static func plainText(_ markdown: String) -> String {
        InlineMarkdown.spans(in: markdown).map(\.text).joined()
    }

    /// Eight hexadecimal digits from `text` (FNV-1a), the same every time.
    static func hash(_ text: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - digits.count) + digits
    }
}
