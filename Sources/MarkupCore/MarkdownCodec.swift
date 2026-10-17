/// One line of a document: its text without any Markdown heading or list
/// marker, its style, and its list item if it is one. List items are always
/// paragraph style.
public struct Line: Equatable, Sendable {
    public var style: BlockStyle
    public var text: String
    public var list: ListItem?

    public init(style: BlockStyle, text: String, list: ListItem? = nil) {
        self.style = style
        self.text = text
        self.list = list
    }
}

/// Converts between Markdown and lines. `markdown(from: lines(fromMarkdown: m))`
/// returns `m` unchanged for any `m` that uses "\n" line endings.
///
/// - A line starting with one to three `#` followed by a space (or nothing)
///   is a heading.
/// - A line starting with an even number of spaces and "- " is a list item,
///   nested one level per two spaces. "[ ] " or "[x] " after the dash makes
///   it a task.
///
/// Text that would otherwise read back as one of these is escaped with a
/// backslash, so it survives a save: a paragraph "# not a heading" is written
/// as "\# not a heading", and a bullet "[ ] not a task" as "- \[ ] not a task".
public enum MarkdownCodec {
    public static func lines(fromMarkdown markdown: String) -> [Line] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).map(line)
    }

    public static func markdown(from lines: [Line]) -> String {
        lines.map(markdown).joined(separator: "\n")
    }

    /// The list item that `text` starts with, and the length of its Markdown
    /// prefix. The prefix is ASCII, so the length is the same in characters
    /// and in UTF-16 units.
    public static func listPrefix(of text: some StringProtocol) -> (item: ListItem, length: Int)? {
        let spaces = text.prefix(while: { $0 == " " }).count
        guard spaces.isMultiple(of: 2) else { return nil }
        let rest = text.dropFirst(spaces)
        guard rest.hasPrefix("- ") else { return nil }
        let marker = taskMarker(of: rest.dropFirst(2)) ?? .bullet
        return (ListItem(level: spaces / 2, marker: marker), spaces + 2 + marker.markdown.count)
    }

    /// The task box that `text` starts with: "[ ] " or "[x] ".
    public static func taskMarker(of text: some StringProtocol) -> ListMarker? {
        if text.hasPrefix(ListMarker.unchecked.markdown) { return .unchecked }
        if text.hasPrefix(ListMarker.checked.markdown) { return .checked }
        return nil
    }

    private static func line(fromMarkdown raw: Substring) -> Line {
        if let line = structuredLine(raw) {
            return line
        }
        let spaces = raw.prefix(while: { $0 == " " })
        let rest = raw.dropFirst(spaces.count)
        if rest.first == "\\", structuredLine(Substring(spaces + rest.drop(while: { $0 == "\\" }))) != nil {
            return Line(style: .paragraph, text: String(spaces) + rest.dropFirst())
        }
        return Line(style: .paragraph, text: String(raw))
    }

    /// The heading or list item that `raw` is, or nil for a paragraph.
    private static func structuredLine(_ raw: Substring) -> Line? {
        if let level = headingLevel(of: raw), let style = BlockStyle(rawValue: level) {
            return Line(style: style, text: String(raw.dropFirst(level + 1)))
        }
        if let prefix = listPrefix(of: raw) {
            var text = raw.dropFirst(prefix.length)
            if prefix.item.marker == .bullet, text.first == "\\",
               taskMarker(of: text.drop(while: { $0 == "\\" })) != nil {
                text = text.dropFirst()
            }
            return Line(style: .paragraph, text: String(text), list: prefix.item)
        }
        return nil
    }

    private static func markdown(from line: Line) -> String {
        if let item = line.list {
            let needsEscape = item.marker == .bullet && taskMarker(of: line.text.drop(while: { $0 == "\\" })) != nil
            return item.markdown + (needsEscape ? "\\" : "") + line.text
        }
        guard line.style != .paragraph else {
            let spaces = line.text.prefix(while: { $0 == " " })
            let rest = line.text.dropFirst(spaces.count)
            let needsEscape = structuredLine(Substring(spaces + rest.drop(while: { $0 == "\\" }))) != nil
            return needsEscape ? String(spaces) + "\\" + rest : line.text
        }
        let marker = String(repeating: "#", count: line.style.rawValue)
        return line.text.isEmpty ? marker : marker + " " + line.text
    }

    /// The level of a heading marker at the start of `text`: one to three `#`
    /// followed by a space or the end of the line.
    private static func headingLevel(of text: Substring) -> Int? {
        let level = text.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(level) else { return nil }
        let rest = text.dropFirst(level)
        return rest.isEmpty || rest.first == " " ? level : nil
    }
}
