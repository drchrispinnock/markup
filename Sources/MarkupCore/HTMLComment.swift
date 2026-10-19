/// HTML comments, `<!-- ... -->`, which Markdown passes through and the
/// formatted view hides.
public enum HTMLComment {
    private static let opening = Array("<!--".utf16)
    private static let closing = Array("-->".utf16)

    /// The comments in `text`, with their ranges as UTF-16 offsets. A
    /// comment with no end isn't one.
    public static func ranges(in text: some StringProtocol) -> [Range<Int>] {
        let units = Array(text.utf16)
        var ranges: [Range<Int>] = []
        var index = 0
        while let start = find(opening, in: units, from: index) {
            guard let end = find(closing, in: units, from: start + opening.count) else { break }
            ranges.append(start..<end + closing.count)
            index = end + closing.count
        }
        return ranges
    }

    /// Whether `text` opens a comment that it doesn't close, so it carries
    /// on to the following lines.
    public static func opensUnclosed(_ text: some StringProtocol) -> Bool {
        let units = Array(text.utf16)
        let end = ranges(in: text).last?.upperBound ?? 0
        return find(opening, in: units, from: end) != nil
    }

    /// Whether `text` contains the end of a comment.
    static func closes(_ text: some StringProtocol) -> Bool {
        find(closing, in: Array(text.utf16), from: 0) != nil
    }

    private static func find(_ pattern: [UInt16], in units: [UInt16], from start: Int) -> Int? {
        guard units.count >= pattern.count, start <= units.count - pattern.count else { return nil }
        return (start...(units.count - pattern.count)).first { units[$0..<$0 + pattern.count].elementsEqual(pattern) }
    }
}
