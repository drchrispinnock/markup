/// How a list item is marked: a bullet, or a checkbox.
public enum ListMarker: Int, Sendable {
    case bullet = 0
    case unchecked = 1
    case checked = 2

    /// The Markdown after the "- ": the task box, if any.
    var markdown: String {
        switch self {
        case .bullet: ""
        case .unchecked: "[ ] "
        case .checked: "[x] "
        }
    }
}

public struct ListItem: Equatable, Sendable {
    /// The nesting depth, 0 for a top-level item.
    public var level: Int
    public var marker: ListMarker

    public init(level: Int, marker: ListMarker) {
        self.level = level
        self.marker = marker
    }

    /// The Markdown that starts the line: two spaces per level, "- ", then
    /// the task box, if any.
    public var markdown: String {
        String(repeating: "  ", count: level) + "- " + marker.markdown
    }
}
