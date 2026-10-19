/// A style that applies to part of a line.
public enum InlineStyle: CaseIterable, Sendable {
    case bold
    case italic
    case strikethrough

    /// The delimiter written on each side: `**bold**`, `*italic*`,
    /// `~~strikethrough~~`.
    public var delimiter: String {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .strikethrough: "~~"
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

    public init(_ text: String, bold: Bool = false, italic: Bool = false, strikethrough: Bool = false) {
        self.init(text, styles: Set([bold ? .bold : nil, italic ? .italic : nil, strikethrough ? .strikethrough : nil]
            .compactMap { $0 }))
    }

    public var bold: Bool { styles.contains(.bold) }
    public var italic: Bool { styles.contains(.italic) }
    public var strikethrough: Bool { styles.contains(.strikethrough) }
}

/// Bold, italic and strikethrough text within a line: `**bold**`,
/// `*italic*`, `***both***` and `~~strikethrough~~`. Images are kept whole,
/// as their Markdown. A backslash makes an asterisk or tilde literal (`\*`,
/// `\~`).
///
/// Delimiters are matched much as CommonMark (and GitHub, for
/// strikethrough) match them: a run of asterisks, or two tildes, can open if
/// it isn't followed by whitespace, and can close if it isn't preceded by
/// whitespace. CommonMark's "rule of 3" applies to asterisk runs that can do
/// both. Underscores aren't read as emphasis.
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
    /// Literal asterisks and tildes are escaped only if they would otherwise
    /// be read as delimiters.
    public static func markdown(for spans: [InlineSpan]) -> String {
        let units = units(of: spans)
        let plain = write(units, escaping: false)
        return Self.spans(in: plain) == merged(units) ? plain : write(units, escaping: true)
    }

    // MARK: - Reading

    private static let star = UInt16(UInt8(ascii: "*"))
    private static let tilde = UInt16(UInt8(ascii: "~"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    private enum Token {
        case text([UInt16])
        /// A run of `length` asterisks or tildes. Those not yet used are
        /// lo..<hi.
        case delimiter(character: UInt16, lo: Int, hi: Int, length: Int, canOpen: Bool, canClose: Bool)
    }

    private static func parse(_ text: String) -> (spans: [InlineSpan], emphases: [Emphasis]) {
        let units = Array(text.utf16)
        let images = MarkdownImage.images(in: text).map(\.range)

        var tokens: [Token] = []
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
            if let image = images.first(where: { $0.lowerBound == index }) {
                appendText(units[image])
                index = image.upperBound
            } else if unit == backslash, index + 1 < units.count, units[index + 1] == star || units[index + 1] == tilde {
                appendText([units[index + 1]])
                index += 2
            } else if unit == star || unit == tilde {
                var end = index
                while end < units.count, units[end] == unit { end += 1 }
                // Only a pair of tildes marks strikethrough.
                guard unit == star || end - index == 2 else {
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
        // that it may close. Asterisks are used two at a time (bold) where
        // both runs have two, else one (italic). Openers between the two can
        // no longer be closed.
        var emphases: [Emphasis] = []
        var regions: [(opener: Int, closer: Int, style: InlineStyle)] = []
        var openers: [Int] = []
        for closer in tokens.indices {
            guard case .delimiter(let character, var lo, let hi, let length, let canOpen, let canClose) = tokens[closer]
            else { continue }
            while canClose, lo < hi, let position = openers.lastIndex(where: { opener in
                guard case .delimiter(let openerCharacter, _, _, let openerLength, _, let openerCanClose) = tokens[opener],
                      openerCharacter == character else { return false }
                // The rule of 3: an asterisk run that can both open and
                // close doesn't match one whose combined length is a
                // multiple of 3, unless both lengths are.
                return character == tilde || !((canOpen || openerCanClose) && (length + openerLength) % 3 == 0
                                               && !(length % 3 == 0 && openerLength % 3 == 0))
            }) {
                let opener = openers[position]
                guard case .delimiter(_, let openerLo, var openerHi, let openerLength, let openerCanOpen,
                                      let openerCanClose) = tokens[opener] else { break }
                let used = character == tilde || (hi - lo >= 2 && openerHi - openerLo >= 2) ? 2 : 1
                let style: InlineStyle = character == tilde ? .strikethrough : used == 2 ? .bold : .italic
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
            switch token {
            case .text(let units): text = units
            case .delimiter(let character, let lo, let hi, _, _, _): text = Array(repeating: character, count: hi - lo)
            }
            guard !text.isEmpty else { continue }
            let styles = Set(regions.filter { $0.opener < index && index < $0.closer }.map(\.style))
            if let last = spans.last, last.styles == styles {
                spans[spans.count - 1].text += String(decoding: text, as: UTF16.self)
            } else {
                spans.append(InlineSpan(String(decoding: text, as: UTF16.self), styles: styles))
            }
        }
        return (spans, emphases.sorted { $0.opening.lowerBound < $1.opening.lowerBound })
    }

    // MARK: - Writing

    /// A character, or a whole image, with its styles.
    private struct Unit {
        var text: String
        var isImage: Bool
        var styles: Set<InlineStyle>
        var isSpace: Bool { !isImage && text.allSatisfy(\.isWhitespace) }
    }

    private static func units(of spans: [InlineSpan]) -> [Unit] {
        var units: [Unit] = []
        for span in spans {
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
        for style in InlineStyle.allCases {
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
            let wanted = open.filter { isWanted($0, at: index) }
                + [InlineStyle.strikethrough, .bold, .italic].filter { isWanted($0, at: index) && !open.contains($0) }
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
            markdown += escaping && !unit.isImage && (unit.text == "*" || unit.text == "~") ? "\\" + unit.text : unit.text
        }
        return markdown
    }
}
