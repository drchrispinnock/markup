import AppKit
import MarkupCore

extension EditorWindowController {
    /// Turns Markdown syntax typed (or pasted) in the edited lines into what
    /// it stands for:
    /// - "# ", "## " and "### " make the line a heading of that level.
    /// - "- " makes a paragraph a bullet, and "[ ] " or "[x] " at the start of
    ///   a bullet makes it a checkbox.
    /// - "![alt](path)" anywhere in a line becomes the image.
    ///
    /// Only edits to the syntax itself trigger this, so an undone conversion
    /// stays undone while the rest of the line is edited.
    ///
    /// Also deletes list markers that have ended up inside a line, as happens
    /// when a list line is joined onto the end of another line.
    func applyMarkdownShortcuts(after edit: NSRange) {
        guard NSMaxRange(edit) <= storage.length else { return }
        // Top down, so each line's nesting limit sees the line above already
        // converted. Conversions shorten the text, so track the end of the
        // edited lines as a distance from the end of the document.
        let span = (storage.string as NSString).paragraphRange(for: edit)
        let distanceFromEnd = storage.length - NSMaxRange(span)
        var location = span.location
        while location < storage.length - distanceFromEnd {
            removeMarkers(insideLineAt: lineRange(at: location))
            let line = lineRange(at: location)
            if let item = listItem(at: line) {
                convertTaskPrefix(of: line, item: item, after: edit)
            } else if !convertHeadingPrefix(of: line, after: edit) {
                convertListPrefix(of: line, after: edit)
            }
            convertImages(in: lineRange(at: location), after: edit)
            location = NSMaxRange(lineRange(at: location))
        }
    }

    /// Removes a typed "# ", "## " or "### " and gives the line that heading
    /// style. Returns false if the line doesn't start with one.
    private func convertHeadingPrefix(of line: NSRange, after edit: NSRange) -> Bool {
        guard line.length > 0 else { return false }
        let text = (storage.string as NSString).substring(with: contentsRange(of: line))
        guard let prefix = MarkdownCodec.headingPrefix(of: text), edit.location < line.location + prefix.length else {
            return false
        }

        let selection = textView.selectedRange()
        // If the line is the last and holds only the prefix, it is left with
        // no characters to carry the style, so remember it for that spot.
        emptyLineStyle = (line.location, prefix.style)
        replaceCharacters(in: NSRange(location: line.location, length: prefix.length), with: NSAttributedString())

        let heading = lineRange(at: line.location)
        if heading.length > 0 {
            changeAttributes(in: heading) {
                storage.addAttributes(prefix.style.attributes, range: heading)
            }
        }
        let afterPrefix = line.location + prefix.length
        let caret = selection.location >= afterPrefix ? selection.location - prefix.length : line.location
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        return true
    }

    /// Replaces typed or pasted image Markdown that the edit touched with
    /// the image.
    private func convertImages(in line: NSRange, after edit: NSRange) {
        let contents = contentsRange(of: line)
        let string = storage.string as NSString
        for match in MarkdownImage.images(in: string.substring(with: contents)).reversed() {
            let range = NSRange(location: contents.location + match.range.lowerBound, length: match.range.count)
            let touched = edit.length > 0
                ? NSIntersectionRange(range, edit).length > 0
                : range.location < edit.location && edit.location < NSMaxRange(range)
            // An attachment inside the syntax, such as an image in the alt
            // text, would be lost.
            guard touched, string.rangeOfCharacter(from: CharacterSet(charactersIn: "\u{FFFC}"), range: range).location == NSNotFound
            else { continue }

            let selection = textView.selectedRange()
            let image = match.image.attachmentString(markdown: string.substring(with: range),
                                                     attributes: storage.attributes(at: range.location, effectiveRange: nil),
                                                     folders: imageFolders)
            replaceCharacters(in: range, with: image)
            let caret = selection.location >= NSMaxRange(range) ? selection.location - range.length + 1
                : selection.location > range.location ? range.location + 1
                : selection.location
            textView.setSelectedRange(NSRange(location: caret, length: 0))
        }
    }
}
