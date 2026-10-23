/// How a list item is marked: a bullet, a checkbox, or a number.
public enum ListMarker: Int, Sendable {
    case bullet = 0
    case unchecked = 1
    case checked = 2
    case numbered = 3

    /// The Markdown after the "- ": the task box, if any.
    var markdown: String {
        switch self {
        case .bullet, .numbered: ""
        case .unchecked: "[ ] "
        case .checked: "[x] "
        }
    }
}

public struct ListItem: Sendable {
    /// The nesting depth, 0 for a top-level item.
    public var level: Int
    public var marker: ListMarker
    /// A numbered item's number. Markdown readers number a list from its
    /// first item's number, whatever the others say.
    public var number: Int
    /// The spaces and marker the item was read with, such as "   1) ", so
    /// that it is written back as it was. Nil for an item made anew, which
    /// is written in the usual form.
    public var written: String?

    public init(level: Int, marker: ListMarker, number: Int = 1) {
        self.level = level
        self.marker = marker
        self.number = number
    }

    /// The marker in the usual form: "- ", then the task box, if any, or
    /// the number and ". ".
    public var markerMarkdown: String {
        marker == .numbered ? "\(number). " : "- " + marker.markdown
    }

    /// How far the item's text is from the start of its marker, which is
    /// where the items nested in it start: after "- " or "1. ".
    var contentOffset: Int {
        marker == .numbered ? String(number).count + 2 : 2
    }

    /// The Markdown that starts the line, out of context: two spaces per
    /// level, then the marker. In a document, an item nested in a numbered
    /// one is indented to line up with its text (`MarkdownCodec`).
    public var markdown: String {
        String(repeating: "  ", count: level) + markerMarkdown
    }
}

extension ListItem: Equatable {
    /// Items are equal whatever they were written as, and bullets and tasks
    /// whatever their number.
    public static func == (a: ListItem, b: ListItem) -> Bool {
        a.level == b.level && a.marker == b.marker && (a.marker != .numbered || a.number == b.number)
    }
}

/// A list item's marker at the start of a line, before its level is known.
struct ListPrefix {
    var indent: Int
    var marker: ListMarker
    var number: Int
    /// The marker as written, such as "- [ ] " or "1) ".
    var text: String

    var length: Int { indent + text.count }
    /// The column the item's text starts at, where items nested in it start.
    var contentColumn: Int { indent + (marker == .numbered ? text.count : 2) }

    /// The marker that `line` starts with: any spaces, then "- " and perhaps
    /// a task box, or one to nine digits, "." or ")", and a space.
    init?(of line: some StringProtocol) {
        let indent = line.prefix(while: { $0 == " " }).count
        let rest = line.dropFirst(indent)
        if rest.hasPrefix("- ") {
            let marker = MarkdownCodec.taskMarker(of: rest.dropFirst(2)) ?? .bullet
            self.init(indent: indent, marker: marker, number: 1, text: "- " + marker.markdown)
            return
        }
        let digits = rest.prefix(while: \.isASCIIDigit)
        let after = rest.dropFirst(digits.count)
        guard (1...9).contains(digits.count), let delimiter = after.first, delimiter == "." || delimiter == ")",
              after.dropFirst().first == " ", let number = Int(digits) else { return nil }
        self.init(indent: indent, marker: .numbered, number: number, text: String(digits) + String(delimiter) + " ")
    }

    private init(indent: Int, marker: ListMarker, number: Int, text: String) {
        self.indent = indent
        self.marker = marker
        self.number = number
        self.text = text
    }
}

/// The lists open at a line, as a Markdown reader sees them: each level's
/// item's indent and the column its text starts at. An item is nested in
/// the item above if it starts at or after that item's text (but less than
/// four columns after, which would be code), and is a sibling if it starts
/// between that item's marker and its text. With no item to go in, one
/// indented by up to three spaces starts a list.
struct ListContext {
    private var indents: [Int] = []
    private var columns: [Int] = []

    /// The level an item with `prefix` would have here, or nil if it can't
    /// be an item.
    func level(of prefix: ListPrefix) -> Int? {
        for level in indents.indices.reversed() {
            if prefix.indent >= columns[level], prefix.indent < columns[level] + 4 { return level + 1 }
            if prefix.indent >= indents[level], prefix.indent < columns[level] { return level }
        }
        return prefix.indent <= 3 ? 0 : nil
    }

    /// Takes in an item with `prefix` at `level`.
    mutating func add(_ prefix: ListPrefix, at level: Int) {
        indents = Array(indents.prefix(level)) + [prefix.indent]
        columns = Array(columns.prefix(level)) + [prefix.contentColumn]
    }

    /// Ends the lists, as a line of text does. A blank line doesn't.
    mutating func end() {
        indents = []
        columns = []
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
