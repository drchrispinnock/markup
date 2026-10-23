import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// The nesting level of a list line, on every character of the line.
    static let listLevel = NSAttributedString.Key("MarkupListLevel")
    /// The `ListMarker` raw value, on the attachment character that starts a
    /// list line and draws its bullet or checkbox.
    static let listMarker = NSAttributedString.Key("MarkupListMarker")
    /// A numbered item's number as read or typed, on its marker. Only the
    /// first item of a list uses it: the others count on from there.
    static let listNumber = NSAttributedString.Key("MarkupListNumber")
}

extension ListItem {
    static let indentPerLevel: CGFloat = 20
    static let markerWidth: CGFloat = 22
    /// The width of a numbered item's number, wide enough for "viii.".
    static let numberWidth: CGFloat = 30

    /// The space before the item's text.
    var width: CGFloat { marker == .numbered ? Self.numberWidth : Self.markerWidth }

    /// The attributes of every character of a list line.
    var lineAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = CGFloat(level) * Self.indentPerLevel
        // Wrapped lines line up with the text, not the marker.
        paragraphStyle.headIndent = paragraphStyle.firstLineHeadIndent + width

        var attributes = BlockStyle.paragraph.attributes
        attributes[.paragraphStyle] = paragraphStyle
        attributes[.listLevel] = level
        return attributes
    }

    /// The attachment character that starts the line.
    @MainActor var markerString: NSAttributedString {
        var attributes = lineAttributes
        attributes[.attachment] = attachment
        attributes[.listMarker] = marker.rawValue
        if marker == .numbered { attributes[.listNumber] = number }
        return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
    }

    @MainActor var attachment: NSTextAttachment {
        guard marker != .numbered else {
            let attachment = NSTextAttachment()
            attachment.attachmentCell = NumberMarkerCell()
            return attachment
        }
        let size = NSSize(width: Self.markerWidth, height: 16)
        let attachment = NSTextAttachment()
        attachment.image = NSImage(size: size, flipped: false) { [marker, level] rect in
            Self.drawMarker(marker, level: level, in: rect)
            return true
        }
        // Sit the marker on the text's baseline, centred on lowercase letters.
        attachment.bounds = NSRect(x: 0, y: -3, width: size.width, height: size.height)
        return attachment
    }

    // Drawn when displayed rather than baked into a bitmap, so the colours
    // follow light and dark mode.
    private static func drawMarker(_ marker: ListMarker, level: Int, in rect: NSRect) {
        switch marker {
        case .numbered:
            break
        case .bullet:
            let dot = NSRect(x: 5, y: rect.midY - 3, width: 6, height: 6)
            NSColor.textColor.set()
            switch level % 3 {
            case 0:
                NSBezierPath(ovalIn: dot).fill()
            case 1:
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
                ring.lineWidth = 1
                ring.stroke()
            default:
                NSBezierPath(rect: dot.insetBy(dx: 0.5, dy: 0.5)).fill()
            }
        case .unchecked, .checked:
            let box = NSRect(x: 1, y: rect.midY - 7, width: 14, height: 14)
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            guard marker == .checked else {
                NSColor.secondaryLabelColor.setStroke()
                outline.lineWidth = 1
                outline.stroke()
                return
            }
            NSColor.controlAccentColor.setFill()
            outline.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + 3.5, y: box.midY))
            tick.line(to: NSPoint(x: box.minX + 6, y: box.minY + 3.5))
            tick.line(to: NSPoint(x: box.maxX - 3, y: box.maxY - 3.5))
            tick.lineWidth = 1.8
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            NSColor.white.setStroke()
            tick.stroke()
        }
    }
}

extension ListItem {
    /// How a numbered item at `level` shows `number`: 1., then i., then a.,
    /// and round again.
    static func numberText(_ number: Int, level: Int) -> String {
        switch level % 3 {
        case 0: "\(number)."
        case 1: romanNumeral(number) + "."
        default: letters(number) + "."
        }
    }

    /// `number` in lower-case Roman numerals.
    private static func romanNumeral(_ number: Int) -> String {
        guard number > 0, number < 4000 else { return "\(number)" }
        let values = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
                      (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
        var rest = number
        var text = ""
        for (value, numeral) in values {
            while rest >= value {
                text += numeral
                rest -= value
            }
        }
        return text
    }

    /// `number` as a, b... z, aa, ab...
    private static func letters(_ number: Int) -> String {
        guard number > 0 else { return "\(number)" }
        var rest = number
        var text = ""
        while rest > 0 {
            rest -= 1
            text = String(UnicodeScalar(UInt8(97 + rest % 26))) + text
            rest /= 26
        }
        return text
    }
}

extension NSAttributedString {
    /// The number of the numbered item whose line starts at `lineStart`:
    /// the first item's number (`.listNumber`), counting on one for each
    /// numbered item above it at its level, back to a line that isn't in its
    /// list. Items nested deeper don't count, and don't end it.
    func listNumber(atLineStart lineStart: Int) -> Int {
        guard lineStart < length else { return 1 }
        let level = attribute(.listLevel, at: lineStart, effectiveRange: nil) as? Int ?? 0
        var number = attribute(.listNumber, at: lineStart, effectiveRange: nil) as? Int ?? 1
        var count = 0
        var location = lineStart
        let text = string as NSString
        while location > 0 {
            let above = text.paragraphRange(for: NSRange(location: location - 1, length: 0))
            guard above.length > 0, let raw = attribute(.listMarker, at: above.location, effectiveRange: nil) as? Int
            else { break }
            let aboveLevel = attribute(.listLevel, at: above.location, effectiveRange: nil) as? Int ?? 0
            location = above.location
            if aboveLevel > level { continue }
            guard aboveLevel == level, raw == ListMarker.numbered.rawValue else { break }
            count += 1
            number = attribute(.listNumber, at: above.location, effectiveRange: nil) as? Int ?? 1
        }
        return number + count
    }
}

/// Draws a numbered item's number, worked out from the lines above it when
/// drawn (`listNumber(atLineStart:)`), in its line's font, as "1.", "i." or
/// "a." by level.
final class NumberMarkerCell: NSTextAttachmentCell {
    nonisolated private static func text(at index: Int, in layoutManager: NSLayoutManager?) -> NSAttributedString? {
        guard let storage = layoutManager?.textStorage, index < storage.length else { return nil }
        let level = storage.attribute(.listLevel, at: index, effectiveRange: nil) as? Int ?? 0
        let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let number = ListItem.numberText(storage.listNumber(atLineStart: index), level: level)
        return NSAttributedString(string: number, attributes: [.font: font, .foregroundColor: NSColor.textColor])
    }

    nonisolated override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                                        glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let font = textContainer.layoutManager?.textStorage.flatMap { storage in
            charIndex < storage.length ? storage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont : nil
        } ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return NSRect(x: 0, y: font.descender, width: ListItem.numberWidth, height: font.ascender - font.descender)
    }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int,
                                   layoutManager: NSLayoutManager) {
        Self.text(at: charIndex, in: layoutManager)?.draw(at: cellFrame.origin)
    }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
}
