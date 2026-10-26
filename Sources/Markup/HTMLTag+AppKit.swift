import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// An HTML tag (`HTMLTag`) other than an image, exactly as written, on
    /// the character that stands for it in the formatted view. Saving and
    /// copying write it back unchanged. An `<img>` carries `.markdownImage`
    /// instead, as an image written in Markdown does.
    static let markdownHTML = NSAttributedString.Key("MarkupHTML")
    /// The formats (`Set<HTMLFormat>`) that HTML formatting tags around it,
    /// such as `<strong>` and `</strong>`, give a character, which shape its
    /// font only. It follows from the tags, so saving writes nothing for it.
    static let htmlFormat = NSAttributedString.Key("MarkupHTMLFormat")
}

extension NSMutableAttributedString {
    /// The formats the HTML formatting tags in `line` give its characters
    /// (`HTMLFormat.ranges`), as ranges of the text.
    func htmlFormats(in line: NSRange) -> [(range: NSRange, formats: Set<HTMLFormat>)] {
        var tags: [(range: Range<Int>, tag: HTMLTag)] = []
        enumerateAttribute(.markdownHTML, in: line) { value, run, _ in
            guard let markdown = value as? String, let tag = HTMLTag.tags(in: markdown).first?.tag else { return }
            for index in run.location..<NSMaxRange(run) {
                let offset = index - line.location
                tags.append((offset..<offset + 1, tag))
            }
        }
        var ranges: [(range: NSRange, formats: Set<HTMLFormat>)] = []
        for (range, formats) in HTMLFormat.ranges(in: line.length, tags: tags) {
            let found = NSRange(location: line.location + range.lowerBound, length: range.count)
            // As one run where nothing separates them.
            if let last = ranges.last, last.formats == formats, NSMaxRange(last.range) == found.location {
                ranges[ranges.count - 1].range.length += found.length
            } else {
                ranges.append((found, formats))
            }
        }
        return ranges
    }

    /// Whether the characters of `line` have the formats their tags give.
    func hasHTMLFormats(in line: NSRange) -> Bool {
        var current: [(range: NSRange, formats: Set<HTMLFormat>)] = []
        enumerateAttribute(.htmlFormat, in: line) { value, run, _ in
            if let formats = value as? Set<HTMLFormat> { current.append((run, formats)) }
        }
        let wanted = htmlFormats(in: line)
        return current.count == wanted.count && zip(current, wanted).allSatisfy { $0.range == $1.range && $0.formats == $1.formats }
    }

    /// Gives the characters of `line` the formats their tags give, and the
    /// fonts that go with them.
    func applyHTMLFormats(in line: NSRange) {
        removeAttribute(.htmlFormat, range: line)
        for (range, formats) in htmlFormats(in: line) {
            addAttribute(.htmlFormat, value: formats, range: range)
        }
        applyInlineStyles(in: line)
    }
}

extension HTMLTag {
    /// The character that shows the tag `markdown`, with the line's
    /// `attributes`:
    /// - `<br>` in the middle of a line is a line separator (U+2028), which
    ///   breaks the line where it is without ending it. At the end of a line,
    ///   where the line ends anyway, it is hidden.
    /// - `<img>` is its image, as `![alt](path)` would be.
    /// - `<p>` and `</p>`, and formatting tags such as `<strong>`, are
    ///   hidden, as a comment is. The text between formatting tags takes
    ///   their format (`.htmlFormat`).
    @MainActor
    func attachmentString(markdown: String, attributes: [NSAttributedString.Key: Any], folders: [URL],
                          endsLine: Bool) -> NSAttributedString {
        if let image {
            return image.attachmentString(markdown: markdown, attributes: attributes, folders: folders)
        }
        if kind == .lineBreak, !endsLine {
            var attributes = attributes
            attributes[.markdownHTML] = markdown
            return NSAttributedString(string: "\u{2028}", attributes: attributes)
        }
        let hidden = NSMutableAttributedString(attributedString: HTMLComment.attachmentString(markdown: markdown,
                                                                                               attributes: attributes))
        hidden.removeAttribute(.markdownComment, range: NSRange(location: 0, length: 1))
        hidden.addAttribute(.markdownHTML, value: markdown, range: NSRange(location: 0, length: 1))
        return hidden
    }
}
