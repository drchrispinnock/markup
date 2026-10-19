/// A style that applies to part of a line.
public enum InlineStyle: CaseIterable, Sendable {
    case bold
    case italic
    case strikethrough
    /// Inline code. Its text is literal: nothing inside it is read as
    /// Markdown.
    case code
    case `subscript`
    case superscript

    /// The delimiter written on each side: `**bold**`, `*italic*`,
    /// `~~strikethrough~~`, `` `code` ``, `H~2~O`, `x^2^`. Code needs more
    /// backticks if its text has some.
    public var delimiter: String {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .strikethrough: "~~"
        case .code: "`"
        case .subscript: "~"
        case .superscript: "^"
        }
    }
}

/// A run of text with the same inline styles.
public struct InlineSpan: Equatable, Sendable {
    public var text: String
    public var styles: Set<InlineStyle>

    public init(_ text: String, styles: Set<InlineStyle> = []) {
        self.text = text
        self.styles = styles
    }

    public init(_ text: String, bold: Bool = false, italic: Bool = false, strikethrough: Bool = false,
                code: Bool = false, subscript: Bool = false, superscript: Bool = false) {
        self.init(text, styles: Set([bold ? .bold : nil, italic ? .italic : nil, strikethrough ? .strikethrough : nil,
                                     code ? .code : nil, `subscript` ? .subscript : nil,
                                     superscript ? .superscript : nil].compactMap { $0 }))
    }

    public var bold: Bool { styles.contains(.bold) }
    public var italic: Bool { styles.contains(.italic) }
    public var strikethrough: Bool { styles.contains(.strikethrough) }
    public var code: Bool { styles.contains(.code) }
    public var `subscript`: Bool { styles.contains(.subscript) }
    public var superscript: Bool { styles.contains(.superscript) }
}

/// Bold, italic, strikethrough, code, subscript and superscript within a
/// line: `**bold**`, `*italic*`, `***both***`, `~~strikethrough~~`,
/// `` `code` ``, `H~2~O` and `x^2^`. Images are kept whole, as their
/// Markdown. A backslash makes an asterisk, tilde, backtick or caret literal
/// (`\*`, `\~`, `` \` ``, `\^`).
///
/// Code spans are read first, as in CommonMark: a run of backticks up to the
/// next run of the same length, with the text between taken literally (and
/// one space trimmed from each end if both have one).
///
/// Delimiters are matched much as CommonMark (and GitHub, for
/// strikethrough) match them: a run of asterisks, or of up to three tildes,
/// can open if it isn't followed by whitespace, and can close if it isn't
/// preceded by whitespace. CommonMark's "rule of 3" applies to asterisk runs
/// that can do both. Tildes pair up like asterisks, two for strikethrough and
/// one for subscript, so `~~~x~~~` is both.
///
/// Subscript (`~`) and superscript (`^`) are as in Pandoc: they may be inside
/// a word, and the text between can't contain whitespace (except within
/// code or an image), so `x^2 + y^2` and `a ~ b ~ c` stay as they are.
/// Underscores aren't read as emphasis.
public enum InlineMarkdown {
    /// A styled range found in Markdown, with its opening and closing
    /// delimiters as UTF-16 offsets.
    public struct Emphasis: Equatable, Sendable {
        public var opening: Range<Int>
        public var closing: Range<Int>
        public var style: InlineStyle
    }

    public static func spans(in text: String) -> [InlineSpan] {
        parse(text).spans
    }

    public static func emphases(in text: String) -> [Emphasis] {
        parse(text).emphases
    }

    /// Markdown for `spans`. Spaces at the edges of styled text are written
    /// outside the delimiters, since a style can't start or end with one.
    /// Subscript and superscript can't hold whitespace, so they leave out
    /// spaces. Literal asterisks, tildes and carets are escaped
    /// only if they would otherwise be read as delimiters.
    public static func markdown(for spans: [InlineSpan]) -> String {
        let units = units(of: spans)
        let plain = write(units, escaping: false)
        return Self.spans(in: plain) == merged(units) ? plain : write(units, escaping: true)
    }

    // MARK: - Reading

    private static let star = UInt16(UInt8(ascii: "*"))
    private static let tilde = UInt16(UInt8(ascii: "~"))
    private static let backtick = UInt16(UInt8(ascii: "`"))
    private static let caret = UInt16(UInt8(ascii: "^"))
    private static let escapable = [star, tilde, backtick, caret]
    private static let space = UInt16(UInt8(ascii: " "))
    private static let backslash = UInt16(UInt8(ascii: "\\"))

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    private enum Token {
        case text([UInt16])
        /// A code span's text, and its opening and closing delimiters
        /// (including any trimmed space).
        case code([UInt16], opening: Range<Int>, closing: Range<Int>)
        /// A run of `length` asterisks, tildes or carets. Those
        /// not yet used are
        /// lo..<hi.
        case delimiter(character: UInt16, lo: Int, hi: Int, length: Int, canOpen: Bool, canClose: Bool)
    }

    private static func parse(_ text: String) -> (spans: [InlineSpan], emphases: [Emphasis]) {
        let units = Array(text.utf16)
        let images = MarkdownImage.images(in: text).map(\.range)

        var tokens: [Token] = []
        // Whitespace that is part of the text, not inside code or an image.
        var isTextWhitespace = units.map(isWhitespace)
        func appendText(_ text: some Collection<UInt16>) {
            if case .text(let previous)? = tokens.last {
                tokens[tokens.count - 1] = .text(previous + text)
            } else {
                tokens.append(.text(Array(text)))
            }
        }
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == backslash, index + 1 < units.count, escapable.contains(units[index + 1]) {
                appendText([units[index + 1]])
                index += 2
            } else if unit == backtick {
                var end = index
                while end < units.count, units[end] == backtick { end += 1 }
                guard let closing = closingRun(of: end - index, in: units, from: end) else {
                    appendText(units[index..<end])
                    index = end
                    continue
                }
                var content = Array(units[end..<closing.lowerBound])
                var opening = index..<end, closingRange = closing
                if content.count >= 2, content.first == space, content.last == space, content.contains(where: { $0 != space }) {
                    content = Array(content.dropFirst().dropLast())
                    opening = opening.lowerBound..<opening.upperBound + 1
                    closingRange = closingRange.lowerBound - 1..<closingRange.upperBound
                }
                tokens.append(.code(content, opening: opening, closing: closingRange))
                isTextWhitespace.replaceSubrange(index..<closing.upperBound,
                                                 with: repeatElement(false, count: closing.upperBound - index))
                index = closing.upperBound
            } else if let image = images.first(where: { $0.lowerBound == index }) {
                appendText(units[image])
                isTextWhitespace.replaceSubrange(image, with: repeatElement(false, count: image.count))
                index = image.upperBound
            } else if [star, tilde, caret].contains(unit) {
                var end = index
                while end < units.count, units[end] == unit { end += 1 }
                // Up to three tildes mark strikethrough and subscript, and
                // only a single caret superscript.
                guard unit == star || end - index <= (unit == tilde ? 3 : 1) else {
                    appendText(units[index..<end])
                    index = end
                    continue
                }
                let before = index > 0 ? units[index - 1] : nil
                let after = end < units.count ? units[end] : nil
                tokens.append(.delimiter(character: unit, lo: index, hi: end, length: end - index,
                                         canOpen: after.map { !isWhitespace($0) } ?? false,
                                         canClose: before.map { !isWhitespace($0) } ?? false))
                index = end
            } else {
                appendText([unit])
                index += 1
            }
        }

        // Match each closer with the nearest opener of the same character
        // that it may close. Asterisks and tildes are used two at a time
        // (bold, strikethrough) where both runs have two, else one (italic,
        // subscript). Openers between the two can no longer be closed.
        // Subscript and superscript can't span whitespace.
        var emphases: [Emphasis] = []
        var regions: [(opener: Int, closer: Int, style: InlineStyle)] = []
        var openers: [Int] = []
        for closer in tokens.indices {
            guard case .delimiter(let character, var lo, let hi, let length, let canOpen, let canClose) = tokens[closer]
            else { continue }
            while canClose, lo < hi, let position = openers.lastIndex(where: { opener in
                guard case .delimiter(let openerCharacter, let openerLo, let openerHi, let openerLength, _,
                                      let openerCanClose) = tokens[opener],
                      openerCharacter == character else { return false }
                // Tildes pair with as many tildes, except that a run of three
                // can be split into strikethrough and subscript.
                if character == tilde, hi - lo != openerHi - openerLo, length != 3, openerLength != 3 {
                    return false
                }
                if character == caret || (character == tilde && min(hi - lo, openerHi - openerLo) == 1) {
                    return !isTextWhitespace[openerHi..<lo].contains(true)
                }
                // The rule of 3: an asterisk run that can both open and
                // close doesn't match one whose combined length is a
                // multiple of 3, unless both lengths are.
                return character != star || !((canOpen || openerCanClose) && (length + openerLength) % 3 == 0
                                               && !(length % 3 == 0 && openerLength % 3 == 0))
            }) {
                let opener = openers[position]
                guard case .delimiter(_, let openerLo, var openerHi, let openerLength, let openerCanOpen,
                                      let openerCanClose) = tokens[opener] else { break }
                let used = character == caret ? 1 : hi - lo >= 2 && openerHi - openerLo >= 2 ? 2 : 1
                let style: InlineStyle = switch character {
                case tilde: used == 2 ? .strikethrough : .subscript
                case caret: .superscript
                default: used == 2 ? .bold : .italic
                }
                emphases.append(Emphasis(opening: openerHi - used..<openerHi, closing: lo..<lo + used, style: style))
                regions.append((opener, closer, style))
                openerHi -= used
                lo += used
                tokens[opener] = .delimiter(character: character, lo: openerLo, hi: openerHi, length: openerLength,
                                            canOpen: openerCanOpen, canClose: openerCanClose)
                openers.removeSubrange((openerHi == openerLo ? position : position + 1)...)
            }
            tokens[closer] = .delimiter(character: character, lo: lo, hi: hi, length: length,
                                        canOpen: canOpen, canClose: canClose)
            if canOpen, lo < hi { openers.append(closer) }
        }

        var spans: [InlineSpan] = []
        for (index, token) in tokens.enumerated() {
            let text: [UInt16]
            var styles = Set(regions.filter { $0.opener < index && index < $0.closer }.map(\.style))
            switch token {
            case .text(let units): text = units
            case .code(let units, _, _):
                text = units
                styles.insert(.code)
            case .delimiter(let character, let lo, let hi, _, _, _): text = Array(repeating: character, count: hi - lo)
            }
            guard !text.isEmpty else { continue }
            if let last = spans.last, last.styles == styles {
                spans[spans.count - 1].text += String(decoding: text, as: UTF16.self)
            } else {
                spans.append(InlineSpan(String(decoding: text, as: UTF16.self), styles: styles))
            }
        }
        for case .code(_, let opening, let closing) in tokens {
            emphases.append(Emphasis(opening: opening, closing: closing, style: .code))
        }
        return (spans, emphases.sorted { $0.opening.lowerBound < $1.opening.lowerBound })
    }

    /// The next run of exactly `length` backticks from `start`.
    private static func closingRun(of length: Int, in units: [UInt16], from start: Int) -> Range<Int>? {
        var index = start
        while index < units.count {
            guard units[index] == backtick else { index += 1; continue }
            var end = index
            while end < units.count, units[end] == backtick { end += 1 }
            if end - index == length { return index..<end }
            index = end
        }
        return nil
    }

    // MARK: - Writing

    /// A character, a whole image or a whole code span, with its styles.
    private struct Unit {
        var text: String
        var isImage: Bool
        var styles: Set<InlineStyle>
        var isCode: Bool { styles.contains(.code) }
        var isSpace: Bool { !isImage && !isCode && text.allSatisfy(\.isWhitespace) }
    }

    private static func units(of spans: [InlineSpan]) -> [Unit] {
        var units: [Unit] = []
        for span in spans {
            guard !span.code else {
                units.append(Unit(text: span.text, isImage: false, styles: span.styles))
                continue
            }
            let utf16 = Array(span.text.utf16)
            var index = 0
            for image in MarkdownImage.images(in: span.text).map(\.range) + [utf16.count..<utf16.count] {
                for character in String(decoding: utf16[index..<image.lowerBound], as: UTF16.self) {
                    units.append(Unit(text: String(character), isImage: false, styles: span.styles))
                }
                if !image.isEmpty {
                    units.append(Unit(text: String(decoding: utf16[image], as: UTF16.self), isImage: true,
                                      styles: span.styles))
                }
                index = image.upperBound
            }
        }
        // A style can't start or end with a space, so leave those out.
        // Subscript and superscript can't have any.
        for (index, unit) in units.enumerated() where unit.isSpace {
            units[index].styles.subtract([.subscript, .superscript])
        }
        for style in InlineStyle.allCases where style != .code {
            var start = 0
            while start < units.count {
                guard units[start].styles.contains(style) else { start += 1; continue }
                var end = start
                while end < units.count, units[end].styles.contains(style) { end += 1 }
                var lo = start, hi = end
                while lo < hi, units[lo].isSpace { units[lo].styles.remove(style); lo += 1 }
                while hi > lo, units[hi - 1].isSpace { units[hi - 1].styles.remove(style); hi -= 1 }
                start = end
            }
        }
        return units
    }

    private static func merged(_ units: [Unit]) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        for unit in units {
            if let last = spans.last, last.styles == unit.styles {
                spans[spans.count - 1].text += unit.text
            } else {
                spans.append(InlineSpan(unit.text, styles: unit.styles))
            }
        }
        return spans
    }

    private static func write(_ units: [Unit], escaping: Bool) -> String {
        var markdown = ""
        var open: [InlineStyle] = []   // outermost first
        func isWanted(_ style: InlineStyle, at index: Int) -> Bool {
            index < units.count && units[index].styles.contains(style)
        }
        /// Where the style running at `index` ends.
        func end(of style: InlineStyle, from index: Int) -> Int {
            var end = index
            while isWanted(style, at: end) { end += 1 }
            return end
        }
        for index in 0...units.count {
            // The styles that should be open here, the one that lasts
            // longest outermost, so it can stay open while the others close.
            // Where two overlap without one containing the other, the one
            // ending first is closed and reopened inside.
            // Strikethrough goes outside bold and italic where they start and
            // end together, as in ~~**this**~~.
            // Code is written as a whole span, inside the others.
            let wanted = open.filter { isWanted($0, at: index) }
                + [InlineStyle.strikethrough, .bold, .italic, .superscript, .subscript].filter { isWanted($0, at: index) && !open.contains($0) }
            let desired = wanted.enumerated().sorted { a, b in
                let (endA, endB) = (end(of: a.element, from: index), end(of: b.element, from: index))
                return endA != endB ? endA > endB : a.offset < b.offset
            }.map(\.element)
            var kept = 0
            while kept < open.count, kept < desired.count, open[kept] == desired[kept] { kept += 1 }
            for style in open[kept...].reversed() { markdown += style.delimiter }
            open.removeSubrange(kept...)
            guard index < units.count else { break }
            for style in desired[kept...] {
                markdown += style.delimiter
                open.append(style)
            }
            let unit = units[index]
            if unit.isCode {
                markdown += codeSpan(unit.text)
            } else if escaping, !unit.isImage, ["*", "~", "`", "^"].contains(unit.text) {
                markdown += "\\" + unit.text
            } else {
                markdown += unit.text
            }
        }
        return markdown
    }

    /// `text` as a code span: in a run of backticks that doesn't appear in
    /// it, with spaces added inside if it starts or ends with a backtick, or
    /// with a space at both ends.
    private static func codeSpan(_ text: String) -> String {
        var runs: Set<Int> = []
        var run = 0
        for character in text + " " {
            if character == "`" { run += 1 } else if run > 0 { runs.insert(run); run = 0 }
        }
        var length = 1
        while runs.contains(length) { length += 1 }
        let delimiter = String(repeating: "`", count: length)
        let needsSpaces = text.first == "`" || text.last == "`"
            || (text.count >= 2 && text.first == " " && text.last == " " && text.contains { $0 != " " })
        return needsSpaces ? delimiter + " " + text + " " + delimiter : delimiter + text + delimiter
    }
}
