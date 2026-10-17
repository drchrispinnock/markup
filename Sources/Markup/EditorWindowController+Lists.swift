import AppKit
import MarkupCore

extension EditorWindowController {
    /// Turns Markdown list syntax typed (or pasted) into the edited lines into
    /// list items: "- " at the start of a paragraph makes a bullet, and "[ ] "
    /// or "[x] " at the start of a bullet makes it a checkbox. Only edits to
    /// the syntax itself trigger this, so an undone conversion stays undone
    /// while the rest of the line is edited.
    ///
    /// Also deletes markers that have ended up inside a line, as happens when
    /// a list line is joined onto the end of another line.
    func applyListShortcuts(after edit: NSRange) {
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
            } else {
                convertListPrefix(of: line, after: edit)
            }
            location = NSMaxRange(lineRange(at: location))
        }
    }

    private func removeMarkers(insideLineAt line: NSRange) {
        guard line.length > 1 else { return }
        var strays: [Int] = []
        storage.enumerateAttribute(.listMarker, in: NSRange(location: line.location + 1, length: line.length - 1)) { value, run, _ in
            if value != nil {
                strays.append(contentsOf: run.location..<NSMaxRange(run))
            }
        }
        for index in strays.reversed() {
            replaceCharacters(in: NSRange(location: index, length: 1), with: NSAttributedString())
        }
    }

    private func convertListPrefix(of line: NSRange, after edit: NSRange) {
        guard line.length > 0, storage.blockStyle(at: line.location) == .paragraph else { return }
        let text = (storage.string as NSString).substring(with: contentsRange(of: line))
        guard let prefix = MarkdownCodec.listPrefix(of: text), edit.location < line.location + prefix.length else { return }
        // Nest at most one level deeper than the item above.
        let item = ListItem(level: min(prefix.item.level, maxLevel(forLineAt: line)), marker: prefix.item.marker)
        replaceMarkdownPrefix(NSRange(location: line.location, length: prefix.length), with: item)
    }

    private func convertTaskPrefix(of line: NSRange, item: ListItem, after edit: NSRange) {
        guard item.marker == .bullet else { return }
        let contents = contentsRange(of: line)
        let text = (storage.string as NSString).substring(with: NSRange(location: contents.location + 1, length: contents.length - 1))
        guard let marker = MarkdownCodec.taskMarker(of: text) else { return }
        let prefix = NSRange(location: line.location, length: 1 + 4)
        guard edit.location < NSMaxRange(prefix) else { return }
        replaceMarkdownPrefix(prefix, with: ListItem(level: item.level, marker: marker))
    }

    /// Replaces typed list syntax with a marker, keeping the caret where it
    /// was relative to the text after it.
    private func replaceMarkdownPrefix(_ prefix: NSRange, with item: ListItem) {
        let selection = textView.selectedRange()
        replaceCharacters(in: prefix, with: item.markerString)
        let afterMarker = prefix.location + 1
        let location = selection.location >= NSMaxRange(prefix) ? selection.location - prefix.length + 1 : afterMarker
        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    /// The deepest level the item on `line` may have: one more than the list
    /// item above it, or 0 if the line above isn't a list item.
    private func maxLevel(forLineAt line: NSRange) -> Int {
        guard line.location > 0, let above = listItem(at: lineRange(at: line.location - 1)) else { return 0 }
        return above.level + 1
    }

    // MARK: - Commands

    /// Return in a list item starts another item of the same kind. On an
    /// empty item it moves the item out a level, or ends the list.
    func insertNewlineInList() -> Bool {
        let selection = textView.selectedRange()
        let line = lineRange(at: selection.location)
        guard let item = listItem(at: line) else { return false }

        if selection.length == 0, contentsRange(of: line).length == 1 {
            if item.level > 0 {
                setLevel(item.level - 1, ofLineAt: line)
            } else {
                replaceCharacters(in: NSRange(location: line.location, length: 1), with: NSAttributedString())
                textView.setSelectedRange(NSRange(location: line.location, length: 0))
            }
            updateForSelection()
            return true
        }

        let next = ListItem(level: item.level, marker: item.marker == .bullet ? .bullet : .unchecked)
        let insertion = NSMutableAttributedString(string: "\n", attributes: item.lineAttributes)
        insertion.append(next.markerString)
        replaceCharacters(in: selection, with: insertion)
        textView.setSelectedRange(NSRange(location: selection.location + insertion.length, length: 0))
        updateForSelection()
        return true
    }

    /// Tab and Shift-Tab indent and outdent the selected list items. Returns
    /// false, so that Tab is typed as usual, when no list item is selected.
    func changeListLevel(by delta: Int) -> Bool {
        let lines = lineRanges(in: textView.selectedRange())
        guard lines.contains(where: { listItem(at: $0) != nil }) else { return false }
        for line in lines {
            guard let item = listItem(at: line) else { continue }
            let level = max(0, min(item.level + delta, maxLevel(forLineAt: line)))
            if level != item.level {
                setLevel(level, ofLineAt: line)
            }
        }
        undoManager?.setActionName(delta > 0 ? "Indent" : "Outdent")
        updateForSelection()
        return true
    }

    private func setLevel(_ level: Int, ofLineAt line: NSRange) {
        guard let item = listItem(at: line) else { return }
        let changed = ListItem(level: level, marker: item.marker)
        changeAttributes(in: line) {
            storage.addAttributes(changed.lineAttributes, range: line)
            // Bullets are drawn differently at each level.
            storage.addAttribute(.attachment, value: changed.attachment, range: NSRange(location: line.location, length: 1))
        }
    }

    /// Ticks or unticks the checkbox at `index`. Returns false if there isn't
    /// one there.
    func toggleCheckbox(at index: Int) -> Bool {
        let line = lineRange(at: index)
        guard line.location == index, let item = listItem(at: line), item.marker != .bullet else { return false }
        let toggled = ListItem(level: item.level, marker: item.marker == .checked ? .unchecked : .checked)
        let marker = NSRange(location: index, length: 1)
        changeAttributes(in: marker) {
            storage.addAttributes([.listMarker: toggled.marker.rawValue, .attachment: toggled.attachment], range: marker)
        }
        undoManager?.setActionName(toggled.marker == .checked ? "Check" : "Uncheck")
        return true
    }

    /// Keeps the caret from resting before a list marker, where typing would
    /// put text in front of the bullet. Moving left from just after a marker
    /// goes on to the end of the line above.
    func adjustSelectionAroundListMarker(from oldRange: NSRange, to newRange: NSRange) -> NSRange {
        guard newRange.length == 0 else { return newRange }
        let line = lineRange(at: newRange.location)
        guard newRange.location == line.location, listItem(at: line) != nil else { return newRange }
        if oldRange.length == 0, oldRange.location == line.location + 1, line.location > 0 {
            return NSRange(location: line.location - 1, length: 0)
        }
        return NSRange(location: line.location + 1, length: 0)
    }
}
