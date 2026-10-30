import AppKit
import MarkupCore

extension EditorViewController {
    /// Insert > Leanpub > Main Matter or Back Matter, whose tag is the
    /// division's index in `LeanpubDivision.allCases`: the division at the
    /// caret, on a line of its own, or in a table, below it.
    @objc func insertLeanpubDivision(_ sender: Any?) {
        guard !isShowingMarkdown, !isPlainText, let tag = (sender as? NSMenuItem)?.tag,
              LeanpubDivision.allCases.indices.contains(tag) else { return }
        let division = LeanpubDivision.allCases[tag]
        let text = NSMutableAttributedString(attributedString: division.attachmentString(attributes: BlockStyle.paragraph.attributes))
        let selection = textView.selectedRange()
        let line = lineRange(at: selection.location)
        if isTableLine(line) {
            insertOnLinesOfTheirOwn(text)
        } else {
            // At the caret, on a line of its own: the text before the caret
            // stays on its line, and the text after goes on the next.
            let newline = NSAttributedString(string: "\n", attributes: BlockStyle.paragraph.attributes)
            let contentsEnd = NSMaxRange(contentsRange(of: line))
            if selection.location > line.location { text.insert(newline, at: 0) }
            if NSMaxRange(selection) < contentsEnd { text.append(newline) }
            replaceCharacters(in: selection, with: text)
            textView.setSelectedRange(NSRange(location: selection.location + text.length, length: 0))
            view.window?.makeFirstResponder(textView)
        }
        undoManager?.setActionName("Insert \(division.title)")
    }

    /// Inserts `text`, whole lines without the last newline, on the caret's
    /// line if it is empty, else below it, leaving the caret after it.
    func insertOnLinesOfTheirOwn(_ text: NSMutableAttributedString) {
        var line = lineRange(at: textView.selectedRange().location)
        if isTableLine(line) { line = tableLines(around: line).last! }
        let contents = contentsRange(of: line)
        let location: Int
        if contents.length == 0, !isTableLine(line) {
            location = line.location
        } else if NSMaxRange(contents) == NSMaxRange(line) {
            // The last line, with no newline to end it.
            location = NSMaxRange(line)
            text.insert(NSAttributedString(string: "\n", attributes: BlockStyle.paragraph.attributes), at: 0)
        } else {
            location = NSMaxRange(line)
            text.append(NSAttributedString(string: "\n", attributes: BlockStyle.paragraph.attributes))
        }
        replaceCharacters(in: NSRange(location: location, length: 0), with: text)
        textView.setSelectedRange(NSRange(location: location + text.length, length: 0))
        view.window?.makeFirstResponder(textView)
    }

    /// Makes a paragraph that is exactly `{mainmatter}` (or another
    /// division), typed or pasted, the division. Returns false if it isn't.
    func convertDivisionLine(_ line: NSRange) -> Bool {
        guard line.length > 0, listItem(at: line) == nil, !isTableLine(line),
              storage.blockStyle(at: line.location) == .paragraph else { return false }
        let contents = contentsRange(of: line)
        guard let division = LeanpubDivision(line: (storage.string as NSString).substring(with: contents)) else { return false }
        let selection = textView.selectedRange()
        replaceCharacters(in: contents, with: division.attachmentString(attributes: BlockStyle.paragraph.attributes))
        let caret = selection.location >= NSMaxRange(contents) ? selection.location - contents.length + 1
            : selection.location > contents.location ? contents.location + 1 : selection.location
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        return true
    }
}
