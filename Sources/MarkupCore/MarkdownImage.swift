/// An inline image: `![alt](path)`.
public struct MarkdownImage: Equatable, Sendable {
    public var alt: String
    public var path: String

    public init(alt: String, path: String) {
        self.alt = alt
        self.path = path
    }

    /// The image as Markdown. Backslashes and brackets in the alt text are
    /// escaped, and a path containing spaces or brackets is put in angle
    /// brackets.
    public var markdown: String {
        var escapedAlt = ""
        for character in alt {
            if "\\[]".contains(character) { escapedAlt.append("\\") }
            escapedAlt.append(character)
        }
        return "![\(escapedAlt)]" + LinkDestination.markdown(path)
    }

    /// The images in `text`, in order, with their ranges as UTF-16 offsets.
    /// The path may be in angle brackets and may be followed by a quoted
    /// title, which is ignored. An image preceded by a backslash is text.
    public static func images(in text: String) -> [(range: Range<Int>, image: MarkdownImage)] {
        let units = Array(text.utf16)
        var images: [(range: Range<Int>, image: MarkdownImage)] = []
        var index = 0
        while index + 1 < units.count {
            if units[index] == backslash {
                index += 2
            } else if units[index] == bang, units[index + 1] == openBracket,
                      let (image, end) = image(in: units, at: index) {
                images.append((index..<end, image))
                index = end
            } else {
                index += 1
            }
        }
        return images
    }

    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let bang = UInt16(UInt8(ascii: "!"))
    private static let openBracket = UInt16(UInt8(ascii: "["))
    private static let closeBracket = UInt16(UInt8(ascii: "]"))
    private static let newline = UInt16(UInt8(ascii: "\n"))

    /// The image whose `![` is at `start`, and the offset just past it.
    private static func image(in units: [UInt16], at start: Int) -> (MarkdownImage, Int)? {
        var index = start + 2
        func peek() -> UInt16? { index < units.count ? units[index] : nil }

        var alt: [UInt16] = []
        while let unit = peek(), unit != closeBracket {
            guard unit != newline, unit != openBracket else { return nil }
            if unit == backslash, index + 1 < units.count {
                index += 1
            }
            alt.append(units[index])
            index += 1
        }
        guard peek() == closeBracket else { return nil }
        index += 1
        guard let (path, end) = LinkDestination.parse(units, at: index) else { return nil }
        return (MarkdownImage(alt: String(decoding: alt, as: UTF16.self), path: path), end)
    }
}
