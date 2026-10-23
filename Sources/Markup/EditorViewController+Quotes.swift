import AppKit
import MarkupCore

/// Blockquotes: lines in the Quote style, indented with a bar beside them
/// (`EditorLayoutManager`), saved after "> ". Typing "> " at the start of a
/// paragraph makes it a quote line, as does choosing Quote in the style
/// popup.
extension EditorViewController {
    /// Makes a paragraph that starts with a typed or pasted "> " a quote
    /// line, without the "> ". Typing waits for the space, so ">" can start
    /// other text; a pasted line of just ">" is an empty quote line. Returns
    /// whether it did.
    func convertQuotePrefix(of line: NSRange, after edit: NSRange) -> Bool {
        guard line.length > 0, listItem(at: line) == nil, !isTableLine(line),
              storage.blockStyle(at: line.location) == .paragraph else { return false }
        let contents = contentsRange(of: line)
        let text = (storage.string as NSString).substring(with: contents)
        guard let length = MarkdownCodec.quotePrefixLength(of: text), edit.location < line.location + length else { return false }
        let hasSpace = text.utf16.count >= length && (text as NSString).character(at: length - 1) == 0x20
        guard hasSpace || (edit.length > 1 && contents.length == length) else { return false }

        let selection = textView.selectedRange()
        emptyLineStyle = (line.location, .quote)
        emptyLineFence = nil
        replaceCharacters(in: NSRange(location: line.location, length: length), with: NSAttributedString())
        let quote = lineRange(at: line.location)
        if quote.length > 0 {
            changeAttributes(in: quote) {
                storage.addAttributes(BlockStyle.quote.attributes, range: quote)
                storage.applyInlineStyles(in: quote)
            }
        }
        let caret = selection.location >= line.location + length ? selection.location - length : line.location
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        return true
    }

    /// Return in a quote. At the end of a quote line it starts another. On
    /// an empty last line of a quote it ends the quote, making the line a
    /// paragraph.
    func insertNewlineInQuote() -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let line = lineRange(at: selection.location)
        let style = line.length > 0 ? storage.blockStyle(at: line.location) : styleAtCaretForEmptyLine
        guard style == .quote, listItem(at: line) == nil else { return false }
        let contents = contentsRange(of: line)
        guard selection.location == NSMaxRange(contents) else { return false }

        guard contents.length == 0 else {
            textView.insertNewline(nil)
            // The new line, if it is the empty last line, has no characters
            // to carry the style, so remember it.
            let caret = textView.selectedRange().location
            if lineRange(at: caret).length == 0 { emptyLineStyle = (caret, .quote) }
            updateForSelection()
            return true
        }
        let next = NSMaxRange(line)
        guard next >= storage.length || storage.blockStyle(at: next) != .quote else { return false }
        endQuote(at: line)
        return true
    }

    /// Backspace at the start of a quote line makes it a paragraph, rather
    /// than joining it to the line above.
    func deleteBackwardInQuote() -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let line = lineRange(at: selection.location)
        guard selection.location == line.location, listItem(at: line) == nil else { return false }
        let style = line.length > 0 ? storage.blockStyle(at: line.location) : styleAtCaretForEmptyLine
        guard style == .quote else { return false }
        endQuote(at: line)
        return true
    }

    /// Makes the quote line `line` a paragraph.
    private func endQuote(at line: NSRange) {
        if line.length > 0 {
            changeAttributes(in: line) {
                storage.addAttributes(BlockStyle.paragraph.attributes, range: line)
                storage.applyInlineStyles(in: line)
            }
            undoManager?.setActionName("End Quote")
        }
        emptyLineStyle = (line.location, .paragraph)
        updateForSelection()
    }
}
