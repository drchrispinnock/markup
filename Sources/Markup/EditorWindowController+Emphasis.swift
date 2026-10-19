import AppKit
import MarkupCore

/// Bold, italic and strikethrough: the header's buttons and the Format menu.
/// With text selected they apply the style to it, or take it off if it all
/// already has it. With no selection they change what is typed next.
extension EditorWindowController {
    @objc func toggleBold(_ sender: Any?) {
        toggle(.bold, actionName: "Bold")
    }

    @objc func toggleItalic(_ sender: Any?) {
        toggle(.italic, actionName: "Italic")
    }

    @objc func toggleStrikethrough(_ sender: Any?) {
        toggle(.strikethrough, actionName: "Strikethrough")
    }

    func button(for style: InlineStyle) -> NSButton {
        switch style {
        case .bold: boldButton
        case .italic: italicButton
        case .strikethrough: strikethroughButton
        }
    }

    private func toggle(_ style: InlineStyle, actionName: String) {
        guard !isShowingMarkdown else { return }
        let selection = textView.selectedRange()
        if selection.length == 0 {
            var styles = inlineStylesAtCaret()
            if styles.contains(style) { styles.remove(style) } else { styles.insert(style) }
            typingStyles = (selection.location, styles)
            updateForSelection()
            return
        }
        let turnOn = !isAll(style, in: selection)
        changeAttributes(in: selection) {
            if turnOn {
                storage.addAttribute(style.key, value: true, range: selection)
            } else {
                storage.removeAttribute(style.key, range: selection)
            }
            storage.applyInlineStyles(in: selection)
        }
        undoManager?.setActionName(actionName)
        updateForSelection()
        window?.makeFirstResponder(textView)
    }

    /// Whether every character of `range` that can be styled has `style`.
    /// Newlines and list markers don't count.
    func isAll(_ style: InlineStyle, in range: NSRange) -> Bool {
        let string = storage.string as NSString
        var sawText = false
        for index in range.location..<NSMaxRange(range) {
            guard string.character(at: index) != 0x0A, storage.attribute(.listMarker, at: index, effectiveRange: nil) == nil
            else { continue }
            guard storage.attribute(style.key, at: index, effectiveRange: nil) != nil else { return false }
            sawText = true
        }
        return sawText
    }

    /// The inline styles that typing at the caret gives: those chosen with
    /// the buttons at this spot, else those of the character before the
    /// caret on its line, else of the one after.
    func inlineStylesAtCaret() -> Set<InlineStyle> {
        let selection = textView.selectedRange()
        if selection.length > 0 {
            return storage.inlineStyles(at: selection.location)
        }
        if let chosen = typingStyles, chosen.location == selection.location {
            return chosen.styles
        }
        typingStyles = nil
        let line = lineRange(at: selection.location)
        let contents = contentsRange(of: line)
        let start = listItem(at: line) != nil ? contents.location + 1 : contents.location
        if selection.location > start {
            return storage.inlineStyles(at: selection.location - 1)
        }
        return selection.location < NSMaxRange(contents) ? storage.inlineStyles(at: selection.location) : []
    }

    /// Turns each style's button on if the selection all has the style, or
    /// if typing at the caret would give it.
    func updateInlineStyleButtons() {
        let selection = textView.selectedRange()
        for style in InlineStyle.allCases {
            let isOn = selection.length > 0 ? isAll(style, in: selection) : textView.typingAttributes[style.key] != nil
            button(for: style).state = isOn ? .on : .off
        }
    }
}
