import Foundation

/// Variables in a fenced code block. Leanpub, like everything else, shows a
/// code block exactly as written, comments and all, so a variable's comments
/// can't be inside one. A block with variables is written with their values
/// as plain text, after a comment holding the block as a template, in which
/// `@name@` is a variable:
///
///     <!-- MARKUPCODE
///     Setting up octez-client (@octez@) ...
///     -->
///     ```
///     Setting up octez-client (25.2) ...
///     ```
///
/// Read back, the block's lines hold the variables' Markdown, with the
/// values the block shows, as any other line would. In a template, `@@` is
/// a literal `@`, and `@>` a `>`, so that `-->` is written `--@>` and can't
/// end the comment. Citations stay in the block as written.
public enum CodeTemplate {
    static let opening = "<!-- MARKUPCODE"
    static let closing = "-->"

    /// The comment to write before a code block of `lines`, or nil if they
    /// have no variables.
    public static func comment(for lines: [String]) -> String? {
        let templates = lines.map(template(of:))
        guard templates.contains(where: { $0 != nil }) else { return nil }
        return ([opening] + zip(templates, lines).map { $0 ?? escaped($1) } + [closing]).joined(separator: "\n")
    }

    /// `line` with each variable replaced by its value, as the block shows it.
    public static func values(of line: String) -> String {
        var units = Array(line.utf16)
        for (range, tag) in MarkupTag.tags(in: line).reversed() where tag.kind == .variable {
            units.replaceSubrange(range, with: Array(tag.value.utf16))
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// The template lines of `comment`, a whole comment, or nil if it isn't
    /// a template.
    public static func lines(ofComment comment: String) -> [Substring]? {
        let lines = comment.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2, lines.first == Substring(opening), lines.last == Substring(closing) else { return nil }
        return Array(lines.dropFirst().dropLast())
    }

    /// The block's `code` lines with the variables of `template` in them,
    /// their values read from the code; nil if the code doesn't fit the
    /// template, as when it was edited elsewhere.
    public static func marked(_ code: [Substring], template: [Substring]) -> [String]? {
        guard code.count == template.count else { return nil }
        var marked: [String] = []
        for (line, template) in zip(code, template) {
            let pieces = self.pieces(of: template)
            let pattern = pieces.map { piece in
                switch piece {
                case .text(let text): NSRegularExpression.escapedPattern(for: text)
                case .variable: "(.*?)"
                }
            }.joined()
            let text = String(line)
            guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$", options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            else { return nil }
            var group = 0
            marked.append(pieces.map { piece in
                switch piece {
                case .text(let text): return text
                case .variable(let name):
                    group += 1
                    let value = (text as NSString).substring(with: match.range(at: group))
                    return MarkupTag(name: name, value: value).markdown
                }
            }.joined())
        }
        return marked
    }

    // MARK: - Templates

    private enum Piece {
        case text(String)
        case variable(String)
    }

    /// `line` as a template line, or nil if it has no variables.
    private static func template(of line: String) -> String? {
        let variables = MarkupTag.tags(in: line).filter { $0.tag.kind == .variable }
        guard !variables.isEmpty else { return nil }
        let units = Array(line.utf16)
        var template = ""
        var index = 0
        for (range, tag) in variables {
            template += escaped(String(decoding: units[index..<range.lowerBound], as: UTF16.self)) + "@\(tag.name)@"
            index = range.upperBound
        }
        return template + escaped(String(decoding: units[index...], as: UTF16.self))
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "@", with: "@@").replacingOccurrences(of: "-->", with: "--@>")
    }

    private static func pieces(of template: some StringProtocol) -> [Piece] {
        let characters = Array(template)
        var pieces: [Piece] = []
        var text = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == "@", index + 1 < characters.count else {
                text.append(character)
                index += 1
                continue
            }
            let next = characters[index + 1]
            if next == "@" || next == ">" {
                text.append(next)
                index += 2
                continue
            }
            var end = index + 1
            while end < characters.count, characters[end] != "@", characters[end] != "\n" { end += 1 }
            let name = String(characters[index + 1..<min(end, characters.count)])
            if end < characters.count, characters[end] == "@", MarkupTag.isValid(name: name) {
                if !text.isEmpty { pieces.append(.text(text)) }
                text = ""
                pieces.append(.variable(name))
                index = end + 1
            } else {
                text.append(character)
                index += 1
            }
        }
        if !text.isEmpty { pieces.append(.text(text)) }
        return pieces
    }
}
