/// The style of a line. The raw value is the Markdown heading level, with 0
/// for a paragraph and -1 for code.
public enum BlockStyle: Int, CaseIterable, Sendable {
    case heading = 1
    case subheading = 2
    case subsubheading = 3
    case paragraph = 0
    /// A line of a fenced code block, kept exactly as typed.
    case code = -1

    public var title: String {
        switch self {
        case .heading: "Heading"
        case .subheading: "Subheading"
        case .subsubheading: "Subsubheading"
        case .paragraph: "Paragraph"
        case .code: "Code"
        }
    }
}
