import AppKit
import MarkupCore

/// Links: the header's link button and Format > Link. A link is
/// `.markdownLink` on its text's characters, holding the destination, which
/// can be any reference, not only a URL. Saved as `[text](destination)`.
extension EditorViewController {
    /// Asks for a link for the selection, or for the link the caret is in.
    /// With no selection and no link there, the link is inserted as its own
    /// text.
    @objc func editLink(_ sender: Any?) {
        guard !isShowingMarkdown, let window = view.window else { return }
        let range = linkTargetRange()
        let existing = range.length > 0 ? storage.attribute(.markdownLink, at: range.location, effectiveRange: nil) as? String
            : nil

        let alert = NSAlert()
        alert.messageText = existing == nil ? "Add Link" : "Edit Link"
        alert.informativeText = "A web address, a file, or any other reference."
        let field = NSTextField(string: existing ?? "")
        field.placeholderString = "https://example.com"
        field.widthAnchor.constraint(equalToConstant: 280).isActive = true
        let accessory = NSStackView(views: [NSTextField(labelWithString: "Link:"), field])
        accessory.frame = NSRect(x: 0, y: 0, width: 330, height: 24)
        alert.accessoryView = accessory
        alert.addButton(withTitle: existing == nil ? "Add Link" : "Change Link")
        alert.addButton(withTitle: "Cancel")
        if existing != nil {
            alert.addButton(withTitle: "Remove Link")
        }
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [self] response in
            switch response {
            case .alertFirstButtonReturn:
                setLink(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), in: range)
            case .alertThirdButtonReturn:
                setLink(nil, in: range)
            default:
                break
            }
            window.makeFirstResponder(textView)
        }
    }

    /// The range a link applies to: the selection, or with none, the whole
    /// link the caret is in (or the caret, if it isn't in one).
    func linkTargetRange() -> NSRange {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return selection }
        let contents = contentsRange(of: lineRange(at: selection.location))
        for location in [selection.location - 1, selection.location]
        where location >= contents.location && location < NSMaxRange(contents) {
            var run = NSRange()
            if storage.attribute(.markdownLink, at: location, longestEffectiveRange: &run, in: contents) != nil {
                return run
            }
        }
        return selection
    }

    /// Links `range` to `destination`, or unlinks it if that is nil or
    /// empty. An empty range gets the destination inserted as its text.
    /// Newlines, list markers and code blocks aren't linked.
    func setLink(_ destination: String?, in range: NSRange) {
        let destination = destination.flatMap { $0.isEmpty ? nil : $0 }
        var range = range
        if range.length == 0 {
            guard let destination else { return }
            textView.setSelectedRange(range)
            textView.insertText(destination, replacementRange: range)
            range.length = textView.selectedRange().location - range.location
            guard range.length > 0 else { return }
        }
        changeAttributes(in: range) {
            let string = storage.string as NSString
            for index in range.location..<NSMaxRange(range) {
                let character = NSRange(location: index, length: 1)
                if string.character(at: index) == 0x0A || storage.attribute(.listMarker, at: index, effectiveRange: nil) != nil
                    || storage.blockStyle(at: index) == .code {
                    storage.removeAttribute(.markdownLink, range: character)
                } else if let destination {
                    storage.addAttribute(.markdownLink, value: destination, range: character)
                } else {
                    storage.removeAttribute(.markdownLink, range: character)
                }
            }
            storage.applyInlineStyles(in: range)
        }
        undoManager?.setActionName(destination == nil ? "Remove Link" : "Link")
        updateForSelection()
    }

    /// The link that typing at the caret continues: one the caret is inside,
    /// not at either end of, so typing after a link doesn't extend it.
    /// Typing over a selection keeps the link of its first character.
    func linkForTyping() -> String? {
        let selection = textView.selectedRange()
        guard selection.location < storage.length else { return nil }
        let after = storage.attribute(.markdownLink, at: selection.location, effectiveRange: nil) as? String
        if selection.length > 0 { return after }
        guard selection.location > 0, let after,
              storage.attribute(.markdownLink, at: selection.location - 1, effectiveRange: nil) as? String == after
        else { return nil }
        return after
    }
}
