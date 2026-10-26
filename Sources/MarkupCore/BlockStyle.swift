/// The style of a line. The raw value is the Markdown heading level, with 0
/// for a paragraph, -1 for code, -2 for a table row, -3 for a quote and -4
/// for front matter.
public enum BlockStyle: Int, CaseIterable, Sendable {
    case heading = 1
    case subheading = 2
    case subsubheading = 3
    case paragraph = 0
    /// A line of a fenced code block, kept exactly as typed.
    case code = -1
    /// A line of a blockquote, written after "> ".
    case quote = -3
    /// A row of a table. The editor shows each cell as a paragraph.
    case table = -2
    /// A line of the front matter at the top of a file (`MarkdownCodec`),
    /// kept exactly as it is. The formatted view doesn't show it.
    case frontMatter = -4

    /// Whether this is a heading's style.
    public var isHeading: Bool { rawValue > 0 }

    public var title: String {
        switch self {
        case .heading: "Heading"
        case .subheading: "Subheading"
        case .subsubheading: "Subsubheading"
        case .paragraph: "Paragraph"
        case .code: "Code"
        case .quote: "Quote"
        case .table: "Table"
        case .frontMatter: "Front Matter"
        }
    }
}
