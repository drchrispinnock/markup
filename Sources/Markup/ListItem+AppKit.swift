import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// The nesting level of a list line, on every character of the line.
    static let listLevel = NSAttributedString.Key("MarkupListLevel")
    /// The `ListMarker` raw value, on the attachment character that starts a
    /// list line and draws its bullet or checkbox.
    static let listMarker = NSAttributedString.Key("MarkupListMarker")
}

extension ListItem {
    static let indentPerLevel: CGFloat = 20
    static let markerWidth: CGFloat = 22

    /// The attributes of every character of a list line.
    var lineAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = CGFloat(level) * Self.indentPerLevel
        // Wrapped lines line up with the text, not the marker.
        paragraphStyle.headIndent = paragraphStyle.firstLineHeadIndent + Self.markerWidth

        var attributes = BlockStyle.paragraph.attributes
        attributes[.paragraphStyle] = paragraphStyle
        attributes[.listLevel] = level
        return attributes
    }

    /// The attachment character that starts the line.
    var markerString: NSAttributedString {
        var attributes = lineAttributes
        attributes[.attachment] = attachment
        attributes[.listMarker] = marker.rawValue
        return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
    }

    var attachment: NSTextAttachment {
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
