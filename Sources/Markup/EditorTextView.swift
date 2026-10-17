import AppKit

/// The editor's text view. It passes clicks on list markers to the
/// controller, and lets the controller decide what copied text looks like.
@MainActor
final class EditorTextView: NSTextView {
    /// Called with the character index of a clicked list marker. Returns true
    /// if it handled the click.
    var markerClickHandler: ((Int) -> Bool)?

    /// The plain text to put on the pasteboard for a range of the document.
    var plainTextForCopy: ((NSRange) -> String)?

    override func mouseDown(with event: NSEvent) {
        if let index = markerIndex(at: convert(event.locationInWindow, from: nil)),
           markerClickHandler?(index) == true {
            return
        }
        super.mouseDown(with: event)
    }

    /// The index of the list marker drawn at `point`, in view coordinates.
    func markerIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let textStorage else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard glyphRect.contains(containerPoint) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        return textStorage.attribute(.listMarker, at: index, effectiveRange: nil) != nil ? index : nil
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string, let plainTextForCopy else {
            return super.writeSelection(to: pboard, type: type)
        }
        let text = selectedRanges.map { plainTextForCopy($0.rangeValue) }.joined(separator: "\n")
        return pboard.setString(text, forType: .string)
    }
}
