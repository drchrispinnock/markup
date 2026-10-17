/// The style of a line. The raw value is the Markdown heading level, with 0
/// for a paragraph.
public enum BlockStyle: Int, CaseIterable, Sendable {
    case heading = 1
    case subheading = 2
    case subsubheading = 3
    case paragraph = 0

    public var title: String {
        switch self {
        case .heading: "Heading"
        case .subheading: "Subheading"
        case .subsubheading: "Subsubheading"
        case .paragraph: "Paragraph"
        }
    }
}
