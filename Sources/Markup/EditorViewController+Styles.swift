import AppKit
import MarkupCore

extension EditorViewController {
    /// Gives every line the selection touches the chosen style. List lines
    /// stop being list items.
    @objc func styleChosen(_ sender: NSPopUpButton) {
        guard let style = BlockStyle(rawValue: sender.selectedTag()) else { return }
        let selection = textView.selectedRange()
        var lines = (storage.string as NSString).paragraphRange(for: selection)

        let listLines = lineRanges(in: lines).filter { listItem(at: $0) != nil }
        for line in listLines.reversed() {
            replaceCharacters(in: NSRange(location: line.location, length: 1), with: NSAttributedString())
        }
        lines.length -= listLines.count

        if lines.length > 0 {
            changeAttributes(in: lines) {
                storage.addAttributes(style.attributes, range: lines)
                if style == .code {
                    // Code keeps its text as typed, without inline styles.
                    for inlineStyle in InlineStyle.allCases {
                        storage.removeAttribute(inlineStyle.key, range: lines)
                    }
                } else {
                    storage.removeAttribute(.codeFence, range: lines)
                }
                storage.applyInlineStyles(in: lines)
            }
            undoManager?.setActionName("Change Style")
        }
        if !listLines.isEmpty {
            let location = max(lines.location, selection.location - 1)
            textView.setSelectedRange(NSRange(location: location, length: selection.length == 0 ? 0 : NSMaxRange(lines) - location))
        }
        // An empty last line has no characters to style, so the choice is
        // remembered for it until something is typed.
        let caret = textView.selectedRange().location
        if lineRange(at: caret).length == 0 {
            emptyLineStyle = (caret, style)
            emptyLineFence = nil
        }
        updateForSelection()
        view.window?.makeFirstResponder(textView)
    }

    /// The style of the line containing the caret. An empty last line has no
    /// characters, so it takes the style that would be typed into it.
    private var styleAtCaret: BlockStyle {
        let line = lineRange(at: textView.selectedRange().location)
        guard line.length > 0 else {
            return (textView.typingAttributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
        }
        return storage.blockStyle(at: line.location)
    }

    /// Makes the typing attributes and the popup match the line at the caret.
    /// NSTextView would otherwise carry the previous line's style into the
    /// start of the next one.
    func updateForSelection() {
        guard !isShowingMarkdown else {
            textView.typingAttributes = Self.markdownAttributes
            return
        }
        defer { updateInlineStyleButtons() }
        let inlineStyles = inlineStylesAtCaret()
        let caret = textView.selectedRange().location
        let line = lineRange(at: caret)
        if let item = listItem(at: line) {
            emptyLineStyle = nil
            textView.typingAttributes = item.lineAttributes.withInlineStyles(inlineStyles)
            stylePopUp.selectItem(withTag: BlockStyle.paragraph.rawValue)
            return
        }
        let style: BlockStyle
        if line.length > 0 {
            style = storage.blockStyle(at: line.location)
            emptyLineStyle = nil
        } else if let remembered = emptyLineStyle, remembered.location == caret {
            style = remembered.style
        } else {
            style = .paragraph
            emptyLineStyle = nil
        }
        var attributes = style.attributes.withInlineStyles(inlineStyles)
        if style == .code {
            // New code lines belong to the same block.
            attributes[.codeFence] = line.length > 0
                ? storage.attribute(.codeFence, at: line.location, effectiveRange: nil) : emptyLineFence
        }
        textView.typingAttributes = attributes
        stylePopUp.selectItem(withTag: style.rawValue)
    }

    /// Return at the end of a heading starts a paragraph on the new line.
    func insertNewlineAfterHeading() -> Bool {
        let selection = textView.selectedRange()
        let contents = contentsRange(of: lineRange(at: selection.location))
        guard styleAtCaret != .paragraph, styleAtCaret != .code, selection.length == 0,
              selection.location == NSMaxRange(contents) else {
            return false
        }

        textView.insertNewline(nil)
        let newLine = lineRange(at: textView.selectedRange().location)
        if newLine.length > 0 {
            changeAttributes(in: newLine) {
                storage.addAttributes(BlockStyle.paragraph.attributes, range: newLine)
                storage.applyInlineStyles(in: newLine)
            }
        }
        updateForSelection()
        return true
    }
}
