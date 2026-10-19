/// One line of a document: its text without any Markdown heading or list
/// marker, its style, and its list item if it is one. List items are always
/// paragraph style. The first line of a code block has the block's fence.
public struct Line: Equatable, Sendable {
    public var style: BlockStyle
    public var text: String
    public var list: ListItem?
    public var fence: CodeFence?

    public init(style: BlockStyle, text: String, list: ListItem? = nil, fence: CodeFence? = nil) {
        self.style = style
        self.text = text
        self.list = list
        self.fence = fence
    }
}

/// The opening fence of a code block: its number of backticks and the info
/// string after them (usually a language), kept so the block is written back
/// as it was.
public struct CodeFence: Hashable, Sendable {
    public var backticks: Int
    public var info: String

    public init(backticks: Int = 3, info: String = "") {
        self.backticks = backticks
        self.info = info
    }

    /// The fence as typed on a line of its own, such as "```" or "```swift".
    public init?(line: some StringProtocol) {
        let backticks = line.prefix(while: { $0 == "`" }).count
        let info = line.dropFirst(backticks)
        guard backticks >= 3, !info.contains("`") else { return nil }
        self.init(backticks: backticks, info: String(info))
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
/// - Lines between an opening fence (three or more backticks, then perhaps a
///   language) and the next line of exactly that many backticks are code,
///   kept exactly as they are. A fence with no lines before its closing
///   line, or none at all, is text.
///
/// Text that would otherwise read back as one of these is escaped with a
/// backslash, so it survives a save: a paragraph "# not a heading" is written
/// as "\# not a heading", and a bullet "[ ] not a task" as "- \[ ] not a task".
/// A paragraph that would open a code block is escaped the same way.
///
/// An HTML comment that starts on one line and ends on a later one stays
/// part of the line it starts on, so that line's text holds newlines.
public enum MarkdownCodec {
    public static func lines(fromMarkdown markdown: String) -> [Line] {
        let raw = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var lines: [Line] = []
        var index = 0
        while index < raw.count {
            if let fence = CodeFence(line: raw[index]), let end = closingFence(of: fence, in: raw, after: index) {
                for (offset, text) in raw[index + 1..<end].enumerated() {
                    lines.append(Line(style: .code, text: String(text), fence: offset == 0 ? fence : nil))
                }
                index = end + 1
                continue
            }
            let text = raw[index]
            if text.first == "\\", let fence = CodeFence(line: text.drop(while: { $0 == "\\" })),
               closingFence(of: fence, in: raw, after: index) != nil {
                lines.append(Line(style: .paragraph, text: String(text.dropFirst())))
            } else {
                var line = line(fromMarkdown: text)
                // A comment that carries on over lines is kept with its
                // first line, as it was written.
                if HTMLComment.opensUnclosed(text),
                   let end = raw[(index + 1)...].firstIndex(where: { HTMLComment.closes($0) }) {
                    line.text += "\n" + raw[(index + 1)...end].joined(separator: "\n")
                    index = end
                }
                lines.append(line)
            }
            index += 1
        }
        return lines
    }

    public static func markdown(from lines: [Line]) -> String {
        // Code blocks become their lines between fences. A block starts at a
        // line with a fence or after a line that isn't code.
        var written: [(text: String, isParagraph: Bool)] = []
        var index = 0
        while index < lines.count {
            guard lines[index].style == .code else {
                written.append((markdown(from: lines[index]), lines[index].style == .paragraph && lines[index].list == nil))
                index += 1
                continue
            }
            var end = index + 1
            while end < lines.count, lines[end].style == .code, lines[end].fence == nil { end += 1 }
            var fence = lines[index].fence ?? CodeFence()
            // A line of exactly the fence's backticks would end the block.
            while lines[index..<end].contains(where: { $0.text == String(repeating: "`", count: fence.backticks) }) {
                fence.backticks += 1
            }
            let marker = String(repeating: "`", count: fence.backticks)
            written.append((marker + fence.info, false))
            written += lines[index..<end].map { ($0.text, false) }
            written.append((marker, false))
            index = end
        }
        // Escape paragraphs that would read back as opening a code block,
        // working up so each sees the lines below as they will be written.
        var texts = written.map(\.text)
        for index in written.indices.reversed() where written[index].isParagraph {
            if let fence = CodeFence(line: texts[index].drop(while: { $0 == "\\" })),
               closingFence(of: fence, in: texts.map { Substring($0) }, after: index) != nil {
                texts[index] = "\\" + texts[index]
            }
        }
        return texts.joined(separator: "\n")
    }

    /// The index of the line that closes a code block opened by `fence` on
    /// line `opening`: the next line of exactly the fence's backticks, if
    /// there is one and the block has at least one line.
    private static func closingFence(of fence: CodeFence, in lines: [Substring], after opening: Int) -> Int? {
        let marker = String(repeating: "`", count: fence.backticks)
        guard let end = lines[(opening + 1)...].firstIndex(where: { $0 == marker }), end > opening + 1 else { return nil }
        return end
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

    /// The heading that `text` starts with, as typed: one to three `#` and a
    /// space. Returns the style and the length of the prefix, which is ASCII.
    public static func headingPrefix(of text: some StringProtocol) -> (style: BlockStyle, length: Int)? {
        let level = text.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(level), text.dropFirst(level).first == " ",
              let style = BlockStyle(rawValue: level) else { return nil }
        return (style, level + 1)
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

    /// A line that isn't code.
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
