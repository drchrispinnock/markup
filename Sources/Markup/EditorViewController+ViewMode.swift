import AppKit
import MarkupCore

/// Switching between the formatted text and the raw Markdown. Both views have
/// one line per Markdown line, and the conversion is lossless, so switching
/// keeps the caret on the same line, the same distance from its end.
extension EditorViewController {
    static let markdownAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor.textColor,
        .paragraphStyle: NSParagraphStyle.default,
    ]

    @objc func viewModeChosen(_ sender: NSSegmentedControl) {
        setShowingMarkdown(sender.selectedSegment == 1)
    }

    /// View > Show Markdown.
    @objc func toggleMarkdown(_ sender: Any?) {
        setShowingMarkdown(!isShowingMarkdown)
    }

    func setShowingMarkdown(_ showMarkdown: Bool) {
        guard showMarkdown != isShowingMarkdown else { return }
        let caret = caretPosition()
        let markdown = self.markdown

        textView.breakUndoCoalescing()
        isShowingMarkdown = showMarkdown
        if showMarkdown {
            storage.setAttributedString(NSAttributedString(string: markdown, attributes: Self.markdownAttributes))
        } else {
            load(markdown: markdown)
        }
        // Undo steps refer to places in the text as the other view laid it
        // out, so they can't be replayed here. Clearing them doesn't change
        // whether the document has unsaved changes.
        undoManager?.removeAllActions()

        viewModeControl.selectedSegment = showMarkdown ? 1 : 0
        stylePopUp.isEnabled = !showMarkdown
        imageButton.isEnabled = !showMarkdown
        linkButton.isEnabled = !showMarkdown
        for style in InlineStyle.allCases {
            button(for: style)?.isEnabled = !showMarkdown
        }
        moveCaret(to: caret)
        updateForSelection()
        view.window?.makeFirstResponder(textView)
    }

    /// The caret's line number, and its distance from the end of the line.
    /// Only the start of a line differs between the views, so the distance
    /// from the end points at the same text in both.
    private func caretPosition() -> (line: Int, fromEnd: Int) {
        let caret = textView.selectedRange().location
        let string = storage.string as NSString
        var line = 0
        var location = 0
        while location < caret {
            let newline = string.range(of: "\n", range: NSRange(location: location, length: caret - location))
            guard newline.location != NSNotFound else { break }
            line += 1
            location = NSMaxRange(newline)
        }
        return (line, NSMaxRange(contentsRange(of: lineRange(at: caret))) - caret)
    }

    private func moveCaret(to position: (line: Int, fromEnd: Int)) {
        let string = storage.string as NSString
        var location = 0
        for _ in 0..<position.line {
            let newline = string.range(of: "\n", range: NSRange(location: location, length: string.length - location))
            guard newline.location != NSNotFound else { break }
            location = NSMaxRange(newline)
        }
        let contents = contentsRange(of: lineRange(at: location))
        let caret = max(contents.location, NSMaxRange(contents) - position.fromEnd)
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}

extension EditorViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleMarkdown(_:)):
            menuItem.state = isShowingMarkdown ? .on : .off
        case #selector(toggleBold(_:)):
            menuItem.state = boldButton.state
            return !isShowingMarkdown
        case #selector(toggleItalic(_:)):
            menuItem.state = italicButton.state
            return !isShowingMarkdown
        case #selector(toggleStrikethrough(_:)):
            menuItem.state = strikethroughButton.state
            return !isShowingMarkdown
        case #selector(toggleCode(_:)):
            menuItem.state = codeButton.state
            return !isShowingMarkdown
        case #selector(toggleHighlight(_:)):
            menuItem.state = isOn(.highlight) ? .on : .off
            return !isShowingMarkdown
        case #selector(editLink(_:)):
            return !isShowingMarkdown
        case #selector(toggleSubscript(_:)):
            menuItem.state = subscriptButton.state
            return !isShowingMarkdown
        case #selector(toggleSuperscript(_:)):
            menuItem.state = superscriptButton.state
            return !isShowingMarkdown
        default:
            break
        }
        return true
    }
}
