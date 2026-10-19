import AppKit
import MarkupCore

extension EditorWindowController {
    /// Turns Markdown syntax typed (or pasted) in the edited lines into what
    /// it stands for:
    /// - "# ", "## " and "### " make the line a heading of that level.
    /// - "- " makes a paragraph a bullet, and "[ ] " or "[x] " at the start of
    ///   a bullet makes it a checkbox.
    /// - "*italic*", "**bold**", "***both***" and "~~strikethrough~~"
    ///   anywhere in a line become styled text.
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
            convertEmphasis(in: lineRange(at: location), after: edit)
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
                storage.applyInlineStyles(in: heading)
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

    /// Replaces typed or pasted inline styles that the edit touched, or that
    /// the edit was typed just after, with styled text. A just-typed closing
    /// asterisk or tilde waits for the next character: an asterisk may be
    /// the first of two, and the next character shouldn't take the style.
    private func convertEmphasis(in line: NSRange, after edit: NSRange) {
        let contents = contentsRange(of: line)
        let string = storage.string as NSString
        let typedDelimiter = edit.length == 1 && NSMaxRange(edit) <= string.length
            && [UInt16(UInt8(ascii: "*")), UInt16(UInt8(ascii: "~"))].contains(string.character(at: edit.location))
        let found = InlineMarkdown.emphases(in: string.substring(with: contents)).map { emphasis in
            (opening: NSRange(location: contents.location + emphasis.opening.lowerBound, length: emphasis.opening.count),
             closing: NSRange(location: contents.location + emphasis.closing.lowerBound, length: emphasis.closing.count),
             style: emphasis.style)
        }
        let chosen = found.filter { emphasis in
            let whole = NSUnionRange(emphasis.opening, emphasis.closing)
            let touched = edit.length > 0
                ? NSIntersectionRange(whole, edit).length > 0 || edit.location == NSMaxRange(whole)
                : whole.location < edit.location && edit.location <= NSMaxRange(whole)
            return touched && !(typedDelimiter && NSMaxRange(edit) == NSMaxRange(emphasis.closing))
        }
        guard !chosen.isEmpty else { return }

        let selection = textView.selectedRange()
        changeAttributes(in: contents) {
            for emphasis in chosen {
                let inner = NSRange(location: NSMaxRange(emphasis.opening),
                                    length: emphasis.closing.location - NSMaxRange(emphasis.opening))
                storage.addAttribute(emphasis.style.key, value: true, range: inner)
            }
            storage.applyInlineStyles(in: contents)
        }
        let asterisks = chosen.flatMap { [$0.opening, $0.closing] }.sorted { $0.location > $1.location }
        for range in asterisks {
            replaceCharacters(in: range, with: NSAttributedString())
        }
        let removedBeforeCaret = asterisks.reduce(0) { removed, range in
            removed + max(0, min(NSMaxRange(range), selection.location) - range.location)
        }
        textView.setSelectedRange(NSRange(location: selection.location - removedBeforeCaret, length: 0))
    }
}
