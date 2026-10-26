/// One line of a document: its text without any Markdown heading or list
/// marker, its style, and its list item if it is one. List items are always
/// paragraph style. The first line of a code block has the block's fence. A
/// heading can have an ID (its anchor), which only headings write. A quote
/// line's text is what follows its "> ".
public struct Line: Equatable, Sendable {
    public var style: BlockStyle
    public var text: String
    public var list: ListItem?
    public var fence: CodeFence?
    public var anchor: HeadingAnchor?
    /// The spaces and ">" (and space) a quote line was read with, such as
    /// ">" or "  > ", so that it is written back as it was. None for one
    /// made anew, which is written after "> ". Lines are equal whatever this
    /// is.
    public var quotePrefix = QuotePrefix()

    public init(style: BlockStyle, text: String, list: ListItem? = nil, fence: CodeFence? = nil,
                anchor: HeadingAnchor? = nil) {
        self.style = style
        self.text = text
        self.list = list
        self.fence = fence
        self.anchor = anchor
    }

    public var isHeading: Bool { style.isHeading && list == nil }

    /// A heading with text. The editor saves one without text as an empty
    /// line, so only these have IDs and are listed to link to.
    public var isTitledHeading: Bool { isHeading && !text.isEmpty }
}

/// How a quote line was written: kept so it is written back the same, but
/// not part of what the line is.
public struct QuotePrefix: Equatable, Sendable {
    public var text: String?

    public init(_ text: String? = nil) {
        self.text = text
    }

    public static func == (_: QuotePrefix, _: QuotePrefix) -> Bool { true }
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
/// - A line starting with one to six `#` followed by a space (or nothing)
///   is a heading.
/// - A line starting with "- ", or a number of one to nine digits and "." or
///   ")" and a space, is a list item: a bullet or a numbered item. "[ ] " or
///   "[x] " after the dash makes it a task. Items nest as CommonMark has it
///   (`ListContext`): an item indented to the text of the item above, or up
///   to three columns more, is nested in it. Each item keeps the spaces and
///   marker it was read with, and one made anew is indented to the text of
///   the item it is nested in.
/// - Lines between an opening fence (three or more backticks, then perhaps a
///   language) and the next line of exactly that many backticks are code,
///   kept exactly as they are. A fence with no lines before its closing
///   line, or none at all, is text.
/// - A line starting with up to three spaces and ">" is a quote line: its
///   text is what follows the ">" and one space, if there is one, and isn't
///   read further (so "> # x" is a quote of "# x"). A line following a
///   quote line without its own ">" is a paragraph, though CommonMark would
///   carry the quote on.
/// - A table (`MarkdownTable`) is table lines, kept exactly as they are.
/// - Front matter, as Jekyll, Hugo and Pandoc read it, is front matter
///   lines, kept exactly as they are: from a first line of "---" to the
///   next line of "---" or "...", unless the line after the first is blank
///   (Pandoc's rule, so a file starting with a horizontal rule isn't taken
///   for it). YAML's comments start with "#", so it can't be read as
///   Markdown.
/// - A heading's ID (`HeadingAnchor`) is `{#id: x}` or `{#x}` on the line
///   above it, or `{#x}` at its end, but not both: a heading with one at its
///   end leaves the line above as text.
///
/// Text that would otherwise read back as one of these is escaped with a
/// backslash, so it survives a save: a paragraph "# not a heading" is written
/// as "\# not a heading", "> not a quote" as "\> not a quote", "1. not a
/// list" as "1\. not a list", and a bullet
/// "[ ] not a task" as "- \[ ] not a task".
/// A paragraph that would open a code block, or be a heading's ID, is
/// escaped the same way, and so is a heading ending in what would be its ID.
///
/// An HTML comment that starts on one line and ends on a later one stays
/// part of the line it starts on, so that line's text holds newlines.
public enum MarkdownCodec {
    public static func lines(fromMarkdown markdown: String) -> [Line] {
        let raw = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var lines: [Line] = []
        var lists = ListContext()
        var index = 0
        if let end = frontMatterEnd(in: raw) {
            lines = raw[...end].map { Line(style: .frontMatter, text: String($0)) }
            index = end + 1
        }
        while index < raw.count {
            if let fence = CodeFence(line: raw[index]), let end = closingFence(of: fence, in: raw, after: index) {
                lists.end()
                for (offset, text) in raw[index + 1..<end].enumerated() {
                    lines.append(Line(style: .code, text: String(text), fence: offset == 0 ? fence : nil))
                }
                index = end + 1
                continue
            }
            let startsBlock = { (line: Int) in
                headingLine(raw[line]) != nil || quotePrefixLength(of: raw[line]) != nil || ListPrefix(of: raw[line]) != nil
                    || CodeFence(line: raw[line]) != nil
            }
            if let rows = MarkdownTable.rowCount(startingAt: index, in: raw, startsBlock: startsBlock) {
                lists.end()
                lines += raw[index..<index + rows].map { Line(style: .table, text: String($0)) }
                index += rows
                continue
            }
            if HeadingAnchor(line: raw[index]) != nil, index + 1 < raw.count,
               var heading = headingLine(raw[index + 1]), heading.anchor == nil {
                heading.anchor = HeadingAnchor(line: raw[index])
                lists.end()
                lines.append(heading)
                index += 2
                continue
            }
            let text = raw[index]
            if text.first == "\\", HeadingAnchor(line: text.drop(while: { $0 == "\\" })) != nil, index + 1 < raw.count,
               attachesAnchorAbove(raw[index + 1]) {
                lists.end()
                lines.append(Line(style: .paragraph, text: String(text.dropFirst())))
            } else if text.first == "\\", let fence = CodeFence(line: text.drop(while: { $0 == "\\" })),
               closingFence(of: fence, in: raw, after: index) != nil {
                lists.end()
                lines.append(Line(style: .paragraph, text: String(text.dropFirst())))
            } else {
                var line = line(fromMarkdown: text, lists: &lists)
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
        var written: [(text: String, kind: WrittenKind)] = []
        // The column each level's item's text starts at, where items made
        // anew nested in it start.
        var columns: [Int] = []
        var index = 0
        while index < lines.count {
            guard lines[index].style == .code else {
                let line = lines[index]
                if line.isHeading, let anchor = line.anchor, anchor.form != .attribute {
                    written.append((anchor.markdown, .other))
                }
                if let item = line.list {
                    let prefix = item.written ?? String(repeating: " ", count: indent(ofLevel: item.level, in: columns))
                        + item.markerMarkdown
                    if let read = ListPrefix(of: prefix) {
                        columns = Array(columns.prefix(item.level))
                        while columns.count < item.level { columns.append(columns.last ?? 0) }
                        columns.append(read.contentColumn)
                    }
                    let needsEscape = item.marker == .bullet && taskMarker(of: line.text.drop(while: { $0 == "\\" })) != nil
                    written.append((prefix + (needsEscape ? "\\" : "") + line.text, .list))
                } else {
                    let isParagraph = line.style == .paragraph
                    written.append((markdown(from: line), isParagraph ? .paragraph : .other))
                    if !isParagraph || !line.text.allSatisfy({ $0 == " " }) { columns = [] }
                }
                index += 1
                continue
            }
            columns = []
            var end = index + 1
            while end < lines.count, lines[end].style == .code, lines[end].fence == nil { end += 1 }
            var fence = lines[index].fence ?? CodeFence()
            // A line of exactly the fence's backticks would end the block.
            while lines[index..<end].contains(where: { $0.text == String(repeating: "`", count: fence.backticks) }) {
                fence.backticks += 1
            }
            let marker = String(repeating: "`", count: fence.backticks)
            written.append((marker + fence.info, .other))
            written += lines[index..<end].map { ($0.text, .other) }
            written.append((marker, .other))
            index = end
        }
        // Escape paragraphs that would read back as list items, working down
        // so each sees the lists open above it as they will be read.
        var texts = written.map(\.text)
        var lists = ListContext()
        for index in written.indices {
            switch written[index].kind {
            case .list:
                if let prefix = ListPrefix(of: texts[index]), let level = lists.level(of: prefix) {
                    lists.add(prefix, at: level)
                }
            case .paragraph:
                texts[index] = escapingList(texts[index], lists: lists)
                if !texts[index].allSatisfy({ $0 == " " }) { lists.end() }
            case .other:
                lists.end()
            }
        }
        // Escape paragraphs that would read back as opening a code block, or
        // as the ID of a heading below, working up so each sees the lines
        // below as they will be written.
        for index in written.indices.reversed() where written[index].kind == .paragraph {
            if HeadingAnchor(line: texts[index].drop(while: { $0 == "\\" })) != nil, index + 1 < texts.count,
               attachesAnchorAbove(Substring(texts[index + 1])) {
                texts[index] = "\\" + texts[index]
            } else if let fence = CodeFence(line: texts[index].drop(while: { $0 == "\\" })),
               closingFence(of: fence, in: texts.map { Substring($0) }, after: index) != nil {
                texts[index] = "\\" + texts[index]
            }
        }
        return texts.joined(separator: "\n")
    }

    /// A piece of Markdown that `pieces(of:)` splits off: text, or a fenced
    /// code block's lines.
    public enum Piece: Equatable, Sendable {
        case text(String)
        case code([String], fence: CodeFence)
    }

    /// `markdown` as text and the fenced code blocks between, in order. Each
    /// text piece ends with the newline before the block after it, and a
    /// block is followed by the rest after its closing line's newline: a
    /// block that had one is followed by a piece, if only an empty one.
    public static func pieces(of markdown: String) -> [Piece] {
        let raw = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var pieces: [Piece] = []
        var text: [Substring] = []
        var index = 0
        let flush = { (endsWithNewline: Bool) in
            if !text.isEmpty { pieces.append(.text(text.joined(separator: "\n") + (endsWithNewline ? "\n" : ""))) }
            text = []
        }
        while index < raw.count {
            if let fence = CodeFence(line: raw[index]), let end = closingFence(of: fence, in: raw, after: index) {
                flush(true)
                pieces.append(.code(raw[index + 1..<end].map(String.init), fence: fence))
                index = end + 1
                continue
            }
            text.append(raw[index])
            index += 1
        }
        flush(false)
        return pieces
    }

    /// The front matter at the start of `markdown`, with the newline after
    /// it if there is one, and the rest of `markdown`; nil if there is none.
    public static func frontMatter(in markdown: String) -> (frontMatter: String, body: String)? {
        let raw = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        guard let end = frontMatterEnd(in: raw) else { return nil }
        let frontMatter = raw[...end].joined(separator: "\n") + (end + 1 < raw.count ? "\n" : "")
        return (frontMatter, raw[(end + 1)...].joined(separator: "\n"))
    }

    /// The index of the line that closes the front matter `lines` start
    /// with, if they do. Spaces and tabs may follow each delimiter.
    private static func frontMatterEnd(in lines: [Substring]) -> Int? {
        let isBlank = { (text: Substring) in text.allSatisfy { $0 == " " || $0 == "\t" } }
        let isDelimiter = { (line: Substring, marks: [String]) in
            marks.contains { line.hasPrefix($0) } && isBlank(line.dropFirst(3))
        }
        guard lines.count > 1, isDelimiter(lines[0], ["---"]), !isBlank(lines[1]) else { return nil }
        return lines.indices.dropFirst().first { isDelimiter(lines[$0], ["---", "..."]) }
    }

    /// The index of the line that closes a code block opened by `fence` on
    /// line `opening`: the next line of exactly the fence's backticks, if
    /// there is one and the block has at least one line.
    private static func closingFence(of fence: CodeFence, in lines: [Substring], after opening: Int) -> Int? {
        let marker = String(repeating: "`", count: fence.backticks)
        guard let end = lines[(opening + 1)...].firstIndex(where: { $0 == marker }), end > opening + 1 else { return nil }
        return end
    }

    private enum WrittenKind {
        case paragraph
        case list
        case other
    }

    /// The indent of an item made anew at `level`: that of the text of the
    /// item it is nested in, given each level's text's column.
    private static func indent(ofLevel level: Int, in columns: [Int]) -> Int {
        guard level > 0 else { return 0 }
        return level <= columns.count ? columns[level - 1] : (columns.last ?? 0) + 2 * (level - columns.count)
    }

    /// The list item that `text` starts with, out of context, and the length
    /// of its Markdown prefix: one level per two spaces. The prefix is ASCII,
    /// so the length is the same in characters and in UTF-16 units.
    public static func listPrefix(of text: some StringProtocol) -> (item: ListItem, length: Int)? {
        guard let prefix = ListPrefix(of: text) else { return nil }
        return (ListItem(level: prefix.indent / 2, marker: prefix.marker, number: prefix.number), prefix.length)
    }

    /// The heading that `text` starts with, as typed: one to six `#` and a
    /// space. Returns the style and the length of the prefix, which is ASCII.
    public static func headingPrefix(of text: some StringProtocol) -> (style: BlockStyle, length: Int)? {
        let level = text.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), text.dropFirst(level).first == " ",
              let style = BlockStyle(rawValue: level) else { return nil }
        return (style, level + 1)
    }

    /// The task box that `text` starts with: "[ ] " or "[x] ".
    public static func taskMarker(of text: some StringProtocol) -> ListMarker? {
        if text.hasPrefix(ListMarker.unchecked.markdown) { return .unchecked }
        if text.hasPrefix(ListMarker.checked.markdown) { return .checked }
        return nil
    }

    /// The line that `raw` is, given the lists open above it, which it
    /// updates.
    private static func line(fromMarkdown raw: Substring, lists: inout ListContext) -> Line {
        if let heading = headingLine(raw) {
            lists.end()
            return heading
        }
        if let length = quotePrefixLength(of: raw) {
            lists.end()
            var line = Line(style: .quote, text: String(raw.dropFirst(length)))
            line.quotePrefix = QuotePrefix(String(raw.prefix(length)))
            return line
        }
        if let prefix = ListPrefix(of: raw), let level = lists.level(of: prefix) {
            lists.add(prefix, at: level)
            var text = raw.dropFirst(prefix.length)
            if prefix.marker == .bullet, text.first == "\\", taskMarker(of: text.drop(while: { $0 == "\\" })) != nil {
                text = text.dropFirst()
            }
            var item = ListItem(level: level, marker: prefix.marker, number: prefix.number)
            item.written = String(raw.prefix(prefix.length))
            return Line(style: .paragraph, text: String(text), list: item)
        }
        defer { if !raw.allSatisfy({ $0 == " " }) { lists.end() } }
        let spaces = raw.prefix(while: { $0 == " " })
        let rest = raw.dropFirst(spaces.count)
        if rest.first == "\\", isHeadingOrQuote(Substring(spaces + rest.drop(while: { $0 == "\\" }))) {
            return Line(style: .paragraph, text: String(spaces) + rest.dropFirst())
        }
        if let escape = listEscape(in: raw), escape.backslashes > 0, readsAsList(escape.unescaped, lists: lists) {
            var text = String(raw)
            text.remove(at: text.index(text.startIndex, offsetBy: escape.offset))
            return Line(style: .paragraph, text: text)
        }
        return Line(style: .paragraph, text: String(raw))
    }

    /// Where a backslash goes to keep `text` from reading as a list item:
    /// before the dash, or between a number and its "." or ")"; how many
    /// are there already; and the text without them.
    private static func listEscape(in text: some StringProtocol) -> (offset: Int, backslashes: Int, unescaped: String)? {
        let spaces = text.prefix(while: { $0 == " " })
        let rest = text.dropFirst(spaces.count)
        let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
        // A dash, perhaps after backslashes; or a number then backslashes.
        let start = digits.isEmpty ? rest : rest.dropFirst(digits.count)
        let backslashes = start.prefix(while: { $0 == "\\" }).count
        guard digits.isEmpty || !start.isEmpty else { return nil }
        // A number is escaped after its digits, so a backslash before them
        // is text.
        guard !digits.isEmpty || start.dropFirst(backslashes).first == "-" else { return nil }
        let unescaped = String(spaces) + digits + start.dropFirst(backslashes)
        return (spaces.count + digits.count, backslashes, unescaped)
    }

    /// Whether `text` would read as a list item, with `lists` open above it.
    private static func readsAsList(_ text: String, lists: ListContext) -> Bool {
        ListPrefix(of: text).flatMap(lists.level(of:)) != nil
    }

    /// `text`, a paragraph, with a backslash added if it would read as a
    /// list item, with `lists` open above it, or did before its backslashes.
    private static func escapingList(_ text: String, lists: ListContext) -> String {
        guard let escape = listEscape(in: text), readsAsList(escape.unescaped, lists: lists) else { return text }
        var escaped = text
        escaped.insert("\\", at: escaped.index(escaped.startIndex, offsetBy: escape.offset))
        return escaped
    }

    /// The length of the quote marker that `text` starts with: up to three
    /// spaces, ">", and a space if there is one.
    public static func quotePrefixLength(of text: some StringProtocol) -> Int? {
        let spaces = text.prefix(while: { $0 == " " }).count
        let rest = text.dropFirst(spaces)
        guard spaces <= 3, rest.first == ">" else { return nil }
        return spaces + 1 + (rest.dropFirst().first == " " ? 1 : 0)
    }

    private static func isHeadingOrQuote(_ raw: Substring) -> Bool {
        headingLine(raw) != nil || quotePrefixLength(of: raw) != nil
    }

    /// Whether `raw` is a heading that takes an ID from the line above: one
    /// without one at its end.
    private static func attachesAnchorAbove(_ raw: Substring) -> Bool {
        guard let line = headingLine(raw) else { return false }
        return line.anchor == nil
    }

    /// The heading that `raw` is, or nil. Its text loses the ID at its end,
    /// if it has one.
    private static func headingLine(_ raw: Substring) -> Line? {
        guard let level = headingLevel(of: raw), let style = BlockStyle(rawValue: level) else { return nil }
        let text = String(raw.dropFirst(level + 1))
        if let trailing = HeadingAnchor.trailing(in: text) {
            return Line(style: style, text: trailing.text, anchor: trailing.anchor)
        }
        return Line(style: style, text: HeadingAnchor.unescapingTrailing(text))
    }

    /// A line that isn't code or a list item.
    private static func markdown(from line: Line) -> String {
        guard line.style != .table, line.style != .frontMatter else { return line.text }
        guard line.style != .paragraph else {
            let spaces = line.text.prefix(while: { $0 == " " })
            let rest = line.text.dropFirst(spaces.count)
            let needsEscape = isHeadingOrQuote(Substring(spaces + rest.drop(while: { $0 == "\\" })))
            return needsEscape ? String(spaces) + "\\" + rest : line.text
        }
        guard line.style != .quote else {
            return (line.quotePrefix.text ?? (line.text.isEmpty ? ">" : "> ")) + line.text
        }
        let marker = String(repeating: "#", count: line.style.rawValue)
        // Text ending as an ID would be read as one, unless an ID follows.
        if let anchor = line.anchor, anchor.form == .attribute {
            return marker + " " + (line.text.isEmpty ? "" : line.text + " ") + anchor.markdown
        }
        let text = HeadingAnchor.trailingNeedsEscape(line.text) ? HeadingAnchor.escapingTrailing(line.text) : line.text
        return text.isEmpty ? marker : marker + " " + text
    }

    /// The level of a heading marker at the start of `text`: one to six `#`
    /// followed by a space or the end of the line.
    private static func headingLevel(of text: Substring) -> Int? {
        let level = text.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let rest = text.dropFirst(level)
        return rest.isEmpty || rest.first == " " ? level : nil
    }
}
