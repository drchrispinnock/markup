import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// The `MarkupTag` an attachment character stands for in the formatted
    /// view, which shows its value. Saving and copying write the tag's
    /// Markdown.
    static let markupTag = NSAttributedString.Key("MarkupTag")
}

extension MarkupTag {
    /// The attachment character for this tag, with the line's `attributes`.
    @MainActor
    func attachmentString(attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = TagAttachmentCell()
        var attributes = attributes
        attributes[.attachment] = attachment
        attributes[.markupTag] = self
        attributes[.toolTip] = toolTip
        return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
    }

    /// A code line as typed, with `attributes`, except that its variables
    /// are tags, as elsewhere. Saving writes a block with variables after a
    /// template (`CodeTemplate`).
    @MainActor
    static func codeText(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        for (range, tag) in tags(in: text).reversed() where tag.kind == .variable {
            result.replaceCharacters(in: NSRange(location: range.lowerBound, length: range.count),
                                     with: tag.attachmentString(attributes: attributes))
        }
        return result
    }

    var toolTip: String {
        switch kind {
        case .variable: isUnknown ? "Variable \(name) has no value" : "Variable \(name)"
        case .citation: isUnknown ? "Citation \(name): bibliography.txt has no entry for it" : "Citation \(name)"
        }
    }

    /// The shading behind a variable's or citation's value: blue, or red (as a broken link's)
    /// when it has none.
    @MainActor static let color = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.3, green: 0.5, blue: 1, alpha: 0.3) : NSColor(red: 0.3, green: 0.5, blue: 1, alpha: 0.18)
    }
}

/// Draws a tag's value, in its character's font and colour, on a rounded
/// shading. The tag, font and colour are read from the character, so the
/// cell follows changes to them.
final class TagAttachmentCell: NSTextAttachmentCell {
    nonisolated private static let padding: CGFloat = 3

    /// The value as drawn, in the attributes of the character at `index`.
    nonisolated private static func text(at index: Int, in layoutManager: NSLayoutManager?)
        -> (NSAttributedString, MarkupTag)? {
        guard let storage = layoutManager?.textStorage, index < storage.length,
              let tag = storage.attribute(.markupTag, at: index, effectiveRange: nil) as? MarkupTag else { return nil }
        let attributes = storage.attributes(at: index, effectiveRange: nil)
        let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let color = attributes[.foregroundColor] as? NSColor ?? NSColor.textColor
        return (NSAttributedString(string: tag.value, attributes: [.font: font, .foregroundColor: color]), tag)
    }

    nonisolated override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                                        glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        guard let (text, _) = Self.text(at: charIndex, in: textContainer.layoutManager),
              let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { return .zero }
        let width = ceil(text.size().width) + 2 * Self.padding
        // From the font's descender to its ascender, so the value sits on
        // the line's baseline without making the line taller.
        return NSRect(x: 0, y: font.descender, width: width, height: font.ascender - font.descender)
    }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int,
                                   layoutManager: NSLayoutManager) {
        guard let (text, tag) = Self.text(at: charIndex, in: layoutManager) else { return }
        MainActor.assumeIsolated {
            (tag.isUnknown ? InlineStyle.brokenLinkColor : MarkupTag.color).setFill()
            NSBezierPath(roundedRect: cellFrame, xRadius: 3, yRadius: 3).fill()
        }
        text.draw(at: NSPoint(x: cellFrame.minX + Self.padding, y: cellFrame.minY))
    }

    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}
}
