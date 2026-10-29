import AppKit
import MarkupCore

/// Switching between the formatted text and the raw Markdown. Both views have
/// one line per Markdown line, except for tables, which are one line per cell
/// in the formatted text, and front matter, which only the Markdown view
/// shows, so switching keeps the caret on the same line, the same distance
/// from its end.
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

    /// View > Show Line Numbers, for every editor.
    @objc func toggleLineNumbers(_ sender: Any?) {
        settings.showsLineNumbers.toggle()
    }

    /// The Markdown view's line numbers are shown while the setting is on.
    func updateLineNumbers() {
        guard let scrollView = textView.enclosingScrollView else { return }
        let shows = isShowingMarkdown && settings.showsLineNumbers
        scrollView.hasVerticalRuler = shows
        scrollView.rulersVisible = shows
        (scrollView.verticalRulerView as? LineNumberRulerView)?.updateThickness()
    }

    func setShowingMarkdown(_ showMarkdown: Bool) {
        guard showMarkdown != isShowingMarkdown, !isPlainText else { return }
        let caret = caretPosition()
        let markdown = self.markdown

        textView.breakUndoCoalescing()
        isShowingMarkdown = showMarkdown
        if showMarkdown {
            storage.setAttributedString(NSAttributedString(string: markdown, attributes: Self.markdownAttributes))
            resetLinkCheck()
        } else {
            load(markdown: markdown)
        }
        updateFrontMatterBadge()
        updateLineNumbers()
        // Undo steps refer to places in the text as the other view laid it
        // out, so they can't be replayed here. Clearing them doesn't change
        // whether the document has unsaved changes.
        undoManager?.removeAllActions()
        // Variables weren't kept up to date in the Markdown view.
        if !showMarkdown { updateTags() }

        viewModeControl.selectedSegment = showMarkdown ? 1 : 0
        stylePopUp.isEnabled = !showMarkdown
        imageButton.isEnabled = !showMarkdown
        linkButton.isEnabled = !showMarkdown
        crossLinkButton.isEnabled = !showMarkdown
        tableButton.isEnabled = !showMarkdown
        for style in InlineStyle.allCases {
            button(for: style)?.isEnabled = !showMarkdown
        }
        moveCaret(to: caret)
        updateForSelection()
        view.window?.makeFirstResponder(textView)
    }

    /// The caret's Markdown line number, and its distance from the end of
    /// the line. Only the start of a line differs between the views, so the
    /// distance from the end points at the same text in both. In a table the
    /// caret goes to the start of its row or cell.
    private func caretPosition() -> (line: Int, fromEnd: Int) {
        let caret = textView.selectedRange().location
        let fromEnd = NSMaxRange(contentsRange(of: lineRange(at: caret))) - caret
        guard !isShowingMarkdown else {
            let string = storage.string as NSString
            var line = 0
            var location = 0
            while location < caret {
                let newline = string.range(of: "\n", range: NSRange(location: location, length: caret - location))
                guard newline.location != NSNotFound else { break }
                line += 1
                location = NSMaxRange(newline)
            }
            return (line, fromEnd)
        }
        let lines = markdownLineNumbers()
        let found = lines.last { $0.line.location <= caret } ?? (NSRange(location: 0, length: 0), 0)
        return (found.markdownLine + frontMatterLineCount, isTableLine(found.line) ? Int.max : fromEnd)
    }

    private func moveCaret(to position: (line: Int, fromEnd: Int)) {
        let location = textLocation(ofMarkdownLine: position.line)
        let contents = contentsRange(of: lineRange(at: location))
        let caret = isTableLine(lineRange(at: location)) ? contents.location
            : max(contents.location, NSMaxRange(contents) - min(position.fromEnd, contents.length))
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    /// The start of the text showing Markdown line `markdownLine` (from 0,
    /// counting front matter), or of the last line if there are fewer. In
    /// the formatted view that is the first line showing it: for a table's
    /// delimiter row, the header, and for front matter, the start.
    func textLocation(ofMarkdownLine markdownLine: Int) -> Int {
        guard !isShowingMarkdown else {
            let string = storage.string as NSString
            var location = 0
            for _ in 0..<max(markdownLine, 0) {
                let newline = string.range(of: "\n", range: NSRange(location: location, length: string.length - location))
                guard newline.location != NSNotFound else { break }
                location = NSMaxRange(newline)
            }
            return location
        }
        let lines = markdownLineNumbers()
        let markdownLine = markdownLine - frontMatterLineCount
        let line = lines.last { $0.markdownLine <= markdownLine }?.markdownLine
        return lines.first { $0.markdownLine == line }?.line.location ?? 0
    }

    /// Each line of the formatted text, with the number of the Markdown line
    /// it starts. A table's cells have their row's line, after the header's
    /// delimiter row, and tables next to each other have a blank line
    /// between them in the Markdown.
    private func markdownLineNumbers() -> [(line: NSRange, markdownLine: Int)] {
        var lines: [(line: NSRange, markdownLine: Int)] = []
        var markdownLine = 0
        var location = 0
        var previousWasTable = false
        while location < storage.length {
            let line = lineRange(at: location)
            if isTableLine(line) {
                if previousWasTable { markdownLine += 1 }
                let cells = tableLines(around: line)
                let columns = max(1, tableBlock(at: line.location)?.table.numberOfColumns ?? 1)
                for (index, cell) in cells.enumerated() {
                    let row = index / columns
                    lines.append((cell, markdownLine + (row == 0 ? 0 : row + 1)))
                }
                markdownLine += (cells.count + columns - 1) / columns + 1
                location = NSMaxRange(cells.last!)
                previousWasTable = true
            } else {
                lines.append((line, markdownLine))
                markdownLine += 1
                location = NSMaxRange(line)
                previousWasTable = false
            }
        }
        if storage.length == 0 || string(endsWithNewline: storage) {
            lines.append((NSRange(location: storage.length, length: 0), markdownLine))
        }
        return lines
    }

    private func string(endsWithNewline text: NSTextStorage) -> Bool {
        text.length > 0 && (text.string as NSString).character(at: text.length - 1) == 0x0A
    }
}

extension EditorViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleMarkdown(_:)):
            menuItem.state = isShowingMarkdown ? .on : .off
            return !isPlainText
        case #selector(toggleLineNumbers(_:)):
            menuItem.state = settings.showsLineNumbers ? .on : .off
            return true
        case #selector(reloadImages(_:)):
            return !isShowingMarkdown
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
        case #selector(insertTable(_:)):
            return !isShowingMarkdown
        case #selector(editLink(_:)), #selector(insertCrossLink(_:)), #selector(insertImage(_:)):
            return !isShowingMarkdown
        case #selector(insertVariable(_:)), #selector(insertCitation(_:)):
            return !isShowingMarkdown && !isPlainText
        case #selector(insertBibliography(_:)):
            return !isShowingMarkdown && !isPlainText && tagSources?.bibliography != nil
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
