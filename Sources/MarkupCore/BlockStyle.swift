/// The style of a line. The raw value is the Markdown heading level, with 0
/// for a paragraph, -1 for code and -2 for a table row.
public enum BlockStyle: Int, CaseIterable, Sendable {
    case heading = 1
    case subheading = 2
    case subsubheading = 3
    case paragraph = 0
    /// A line of a fenced code block, kept exactly as typed.
    case code = -1
    /// A row of a table. The editor shows each cell as a paragraph.
    case table = -2

    public var title: String {
        switch self {
        case .heading: "Heading"
        case .subheading: "Subheading"
        case .subsubheading: "Subsubheading"
        case .paragraph: "Paragraph"
        case .code: "Code"
        case .table: "Table"
        }
    }
}
