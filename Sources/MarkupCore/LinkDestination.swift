/// The `(destination "title")` part of an image or link. The destination may
/// be in angle brackets, which it needs if it has spaces or brackets. A
/// title is read past but not kept.
enum LinkDestination {
    private static let openParen = UInt16(UInt8(ascii: "("))
    private static let closeParen = UInt16(UInt8(ascii: ")"))
    private static let lessThan = UInt16(UInt8(ascii: "<"))
    private static let greaterThan = UInt16(UInt8(ascii: ">"))
    private static let quote = UInt16(UInt8(ascii: "\""))
    private static let space = UInt16(UInt8(ascii: " "))
    private static let newline = UInt16(UInt8(ascii: "\n"))

    /// The destination whose `(` is at `start`, and the offset just past
    /// its `)`.
    static func parse(_ units: [UInt16], at start: Int) -> (destination: String, end: Int)? {
        guard start < units.count, units[start] == openParen else { return nil }
        var index = start + 1
        func peek() -> UInt16? { index < units.count ? units[index] : nil }

        var destination: [UInt16] = []
        if peek() == lessThan {
            index += 1
            while let unit = peek(), unit != greaterThan {
                guard unit != newline, unit != lessThan else { return nil }
                destination.append(unit)
                index += 1
            }
            guard peek() == greaterThan else { return nil }
            index += 1
        } else {
            while let unit = peek(), unit != space, unit != newline, unit != openParen, unit != closeParen {
                destination.append(unit)
                index += 1
            }
        }

        while peek() == space { index += 1 }
        if peek() == quote {
            index += 1
            while let unit = peek(), unit != quote {
                guard unit != newline else { return nil }
                index += 1
            }
            guard peek() == quote else { return nil }
            index += 1
            while peek() == space { index += 1 }
        }
        guard peek() == closeParen else { return nil }
        return (String(decoding: destination, as: UTF16.self), index + 1)
    }

    /// `destination` as written in Markdown, in parentheses.
    static func markdown(_ destination: String) -> String {
        destination.contains(where: { " ()<>".contains($0) }) ? "(<\(destination)>)" : "(\(destination))"
    }
}
