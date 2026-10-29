import AppKit
import MarkupCore

extension EditorViewController {
    func removeMarkers(insideLineAt line: NSRange) {
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

    func convertListPrefix(of line: NSRange, after edit: NSRange) {
        guard line.length > 0, storage.blockStyle(at: line.location) == .paragraph else { return }
        let text = (storage.string as NSString).substring(with: contentsRange(of: line))
        guard let prefix = MarkdownCodec.listPrefix(of: text), edit.location < line.location + prefix.length else { return }
        // Nest at most one level deeper than the item above.
        let item = ListItem(level: min(prefix.item.level, maxLevel(forLineAt: line)), marker: prefix.item.marker,
                            number: prefix.item.number)
        replaceMarkdownPrefix(NSRange(location: line.location, length: prefix.length), with: item)
    }

    func convertTaskPrefix(of line: NSRange, item: ListItem, after edit: NSRange) {
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

        // A new task starts unticked.
        let next = ListItem(level: item.level, marker: item.marker == .checked ? .unchecked : item.marker)
        let insertion = NSMutableAttributedString(string: "\n", attributes: item.lineAttributes)
        insertion.append(next.markerString)
        replaceCharacters(in: selection, with: insertion)
        textView.setSelectedRange(NSRange(location: selection.location + insertion.length, length: 0))
        updateForSelection()
        return true
    }

    /// After lines are pasted into list item `item` from `start` to the
    /// caret, makes each line after the first another item like it, as if
    /// Return had been pressed between them, so three lines pasted on a
    /// bullet are three bullets. The line the caret ends on is one of them,
    /// holding the text that was after the caret. Lines the paste's
    /// Markdown made items or headings already are left as they are.
    func continueList(_ item: ListItem, overLinesPastedFrom start: Int) {
        let end = textView.selectedRange().location
        guard end > start else { return }
        var lines = lineRanges(in: NSRange(location: start, length: end - start))
        // A paste ending in a newline ends on the line after the lines it
        // touched.
        if (storage.string as NSString).character(at: end - 1) == 0x0A {
            lines.append(lineRange(at: end))
        }
        let next = ListItem(level: item.level, marker: item.marker == .checked ? .unchecked : item.marker)
        var added = 0
        // From the bottom, so the lines above keep their places.
        for line in lines.dropFirst().reversed() {
            guard listItem(at: line) == nil,
                  line.length == 0 || storage.blockStyle(at: line.location) == .paragraph else { continue }
            replaceCharacters(in: NSRange(location: line.location, length: 0), with: next.markerString)
            added += 1
        }
        textView.setSelectedRange(NSRange(location: end + added, length: 0))
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
            storage.applyInlineStyles(in: line)
            // Bullets are drawn differently at each level.
            storage.addAttribute(.attachment, value: changed.attachment, range: NSRange(location: line.location, length: 1))
        }
    }

    /// Ticks or unticks the checkbox at `index`. Returns false if there isn't
    /// one there.
    func toggleCheckbox(at index: Int) -> Bool {
        let line = lineRange(at: index)
        guard line.location == index, let item = listItem(at: line), item.marker == .checked || item.marker == .unchecked
        else { return false }
        let toggled = ListItem(level: item.level, marker: item.marker == .checked ? .unchecked : .checked)
        let marker = NSRange(location: index, length: 1)
        changeAttributes(in: marker) {
            storage.addAttributes([.listMarker: toggled.marker.rawValue, .attachment: toggled.attachment], range: marker)
        }
        undoManager?.setActionName(toggled.marker == .checked ? "Check" : "Uncheck")
        return true
    }

    // MARK: - Numbers

    /// The Markdown that starts the list line at `lineStart`: indented to
    /// line up with the text of the item it is nested in, as saving writes
    /// it, then its marker, with its number if it has one.
    func markdownPrefix(ofListLineAt lineStart: Int) -> String {
        guard var item = listItem(at: lineRange(at: lineStart)) else { return "" }
        if item.marker == .numbered { item.number = storage.listNumber(atLineStart: lineStart) }
        return String(repeating: " ", count: markdownIndent(ofListLineAt: lineStart)) + item.markerMarkdown
    }

    /// How far the list line at `lineStart` is indented in Markdown: to the
    /// text of the item it is nested in, after its "- " or "1. ".
    private func markdownIndent(ofListLineAt lineStart: Int) -> Int {
        guard let item = listItem(at: lineRange(at: lineStart)), item.level > 0 else { return 0 }
        var location = lineStart
        while location > 0 {
            let above = lineRange(at: location - 1)
            guard let parent = listItem(at: above), parent.level >= item.level - 1 else { break }
            location = above.location
            guard parent.level == item.level - 1 else { continue }
            let marker = parent.marker == .numbered ? "\(storage.listNumber(atLineStart: above.location)). " : "- "
            return markdownIndent(ofListLineAt: above.location) + marker.count
        }
        return item.level * 2
    }

    /// Numbers are worked out from the lines above when drawn, so an edit
    /// can change those of the list items below it, which are redrawn.
    func redrawListNumbers(after edit: NSRange) {
        guard let layoutManager = textView.layoutManager, NSMaxRange(edit) <= storage.length else { return }
        var end = NSMaxRange(lineRange(at: min(NSMaxRange(edit), max(storage.length - 1, 0))))
        while end < storage.length, storage.attribute(.listMarker, at: end, effectiveRange: nil) != nil {
            end = NSMaxRange(lineRange(at: end))
        }
        let start = lineRange(at: min(edit.location, max(storage.length - 1, 0))).location
        guard end > start else { return }
        layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: start, length: end - start))
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
