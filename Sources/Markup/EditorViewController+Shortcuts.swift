import AppKit
import MarkupCore

extension EditorViewController {
    /// Turns Markdown syntax typed (or pasted) in the edited lines into what
    /// it stands for:
    /// - "# ", "## " and "### " make the line a heading of that level.
    /// - "- " makes a paragraph a bullet, and "[ ] " or "[x] " at the start of
    ///   a bullet makes it a checkbox.
    /// - "*italic*", "**bold**", "***both***", "~~strikethrough~~", "`code`",
    ///   "~subscript~", "^superscript^" and "==highlight==" anywhere in a line become styled
    ///   text.
    /// - "![alt](path)" anywhere in a line becomes the image.
    /// - "[text](destination)" anywhere in a line becomes a link.
    /// - "<!-- comment -->" anywhere in a line is hidden.
    /// - "{#id: x}" or "{#x}" alone on the line above a heading becomes the
    ///   heading's ID.
    ///
    /// Lines of code blocks, and inline code, are left as typed.
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
            // Code blocks keep their text as typed.
            if line.length > 0, listItem(at: line) == nil, storage.blockStyle(at: line.location) == .code {
                location = NSMaxRange(line)
                continue
            }
            // An ID typed or pasted above a heading becomes its ID.
            if NSIntersectionRange(line, edit).length > 0 || NSLocationInRange(edit.location, line),
               convertAnchorLine(line) {
                continue
            }
            if isTableLine(line) {
                // A cell can't be a heading or list item.
            } else if let item = listItem(at: line) {
                convertTaskPrefix(of: line, item: item, after: edit)
            } else if convertHeadingPrefix(of: line, after: edit) || (edit.location == line.location && isHeadingLine(line)) {
                // A heading just made, or just given its first character
                // (on an empty last line), takes an ID typed above it.
                if line.location > 0, case let above = lineRange(at: line.location - 1), convertAnchorLine(above) {
                    location = above.location
                    continue
                }
            } else {
                convertListPrefix(of: line, after: edit)
            }
            convertEmphasis(in: lineRange(at: location), after: edit)
            convertImages(in: lineRange(at: location), after: edit)
            convertLinks(in: lineRange(at: location), after: edit)
            convertComments(in: lineRange(at: location), after: edit)
            location = NSMaxRange(lineRange(at: location))
        }
        convertTables(after: edit)
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
        emptyLineFence = nil
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
            guard touched, string.rangeOfCharacter(from: CharacterSet(charactersIn: "\u{FFFC}"), range: range).location == NSNotFound,
                  !isInlineCode(range), !followsUnclosedBacktick(range, in: contents)
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

    /// Hides typed or pasted HTML comments that the edit touched.
    private func convertComments(in line: NSRange, after edit: NSRange) {
        let contents = contentsRange(of: line)
        let string = storage.string as NSString
        for comment in HTMLComment.ranges(in: string.substring(with: contents)).reversed() {
            let range = NSRange(location: contents.location + comment.lowerBound, length: comment.count)
            let touched = edit.length > 0
                ? NSIntersectionRange(range, edit).length > 0
                : range.location < edit.location && edit.location < NSMaxRange(range)
            guard touched, !isInlineCode(range), !followsUnclosedBacktick(range, in: contents) else { continue }

            let selection = textView.selectedRange()
            let hidden = HTMLComment.attachmentString(markdown: string.substring(with: range),
                                                      attributes: storage.attributes(at: range.location, effectiveRange: nil))
            replaceCharacters(in: range, with: hidden)
            let caret = selection.location >= NSMaxRange(range) ? selection.location - range.length + 1
                : selection.location > range.location ? range.location + 1
                : selection.location
            textView.setSelectedRange(NSRange(location: caret, length: 0))
        }
    }

    /// Replaces typed or pasted link Markdown that the edit touched with the
    /// linked text.
    private func convertLinks(in line: NSRange, after edit: NSRange) {
        let contents = contentsRange(of: line)
        let string = storage.string as NSString
        for link in InlineMarkdown.links(in: string.substring(with: contents)).reversed() {
            let range = NSRange(location: contents.location + link.range.lowerBound, length: link.range.count)
            let text = NSRange(location: contents.location + link.text.lowerBound, length: link.text.count)
            let touched = edit.length > 0
                ? NSIntersectionRange(range, edit).length > 0
                : range.location < edit.location && edit.location < NSMaxRange(range)
            guard touched, !isInlineCode(NSRange(location: range.location, length: 1)),
                  !isInlineCode(NSRange(location: NSMaxRange(text), length: NSMaxRange(range) - NSMaxRange(text))),
                  !followsUnclosedBacktick(range, in: contents)
            else { continue }

            let selection = textView.selectedRange()
            changeAttributes(in: text) {
                storage.addAttribute(.markdownLink, value: link.destination, range: text)
                storage.applyInlineStyles(in: text)
            }
            let closing = NSRange(location: NSMaxRange(text), length: NSMaxRange(range) - NSMaxRange(text))
            replaceCharacters(in: closing, with: NSAttributedString())
            replaceCharacters(in: NSRange(location: range.location, length: 1), with: NSAttributedString())
            let caret = selection.location >= NSMaxRange(range) ? selection.location - (range.length - text.length)
                : selection.location > range.location ? min(selection.location - 1, NSMaxRange(text) - 1)
                : selection.location
            textView.setSelectedRange(NSRange(location: caret, length: 0))
        }
    }

    /// Whether an odd number of backticks that aren't inline code come
    /// before `range` on its line, so it may be inside inline code that is
    /// still being typed.
    private func followsUnclosedBacktick(_ range: NSRange, in contents: NSRange) -> Bool {
        let string = storage.string as NSString
        var count = 0
        for index in contents.location..<range.location where string.character(at: index) == UInt16(UInt8(ascii: "`")) {
            if storage.attribute(.inlineCode, at: index, effectiveRange: nil) == nil { count += 1 }
        }
        return count % 2 == 1
    }

    /// Whether any of `range` is already inline code.
    private func isInlineCode(_ range: NSRange) -> Bool {
        var found = false
        storage.enumerateAttribute(.inlineCode, in: range) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// Replaces typed or pasted inline styles that the edit touched, or that
    /// the edit was typed just after, with styled text. A just-typed closing
    /// delimiter (asterisk, tilde, backtick, caret or equals sign) waits for
    /// the next character: an asterisk may be the first of two, and the next
    /// character shouldn't take the style.
    private func convertEmphasis(in line: NSRange, after edit: NSRange) {
        let contents = contentsRange(of: line)
        let string = storage.string as NSString
        let typedDelimiter = edit.length == 1 && NSMaxRange(edit) <= string.length
            && "*~`^=".utf16.contains(string.character(at: edit.location))
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
            // Delimiters inside inline code are code, as are those after an
            // unclosed backtick, which may be inline code still being typed.
            return touched && !(typedDelimiter && NSMaxRange(edit) == NSMaxRange(emphasis.closing))
                && !isInlineCode(emphasis.opening) && !isInlineCode(emphasis.closing)
                && (emphasis.style == .code || !followsUnclosedBacktick(emphasis.opening, in: contents))
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
