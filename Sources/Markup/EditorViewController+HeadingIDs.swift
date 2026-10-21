import AppKit
import MarkupCore

/// Heading IDs (`HeadingAnchor`), which links refer to as `[text](#id)`. The
/// Formatted view doesn't show them: a heading's ID is `.headingAnchor` on
/// every character of its line. The Markdown view shows them as written,
/// where they can be changed by hand. Saving gives every heading without one
/// a new ID (`addMissingHeadingIDs`); one already there is never changed.
extension EditorViewController {
    /// Whether `line` is a heading.
    func isHeadingLine(_ line: NSRange) -> Bool {
        line.length > 0 && listItem(at: line) == nil && storage.blockStyle(at: line.location).rawValue > 0
    }

    /// Whether `line` is a heading with text. One whose text has all been
    /// deleted is saved as an empty line, without its ID, as if deleted.
    func isTitledHeading(_ line: NSRange) -> Bool {
        isHeadingLine(line) && contentsRange(of: line).length > 0
    }

    /// The ID that any character of `line` has.
    func headingAnchor(in line: NSRange) -> HeadingAnchor? {
        var anchor: HeadingAnchor?
        storage.enumerateAttribute(.headingAnchor, in: line) { value, _, stop in
            if let value = value as? HeadingAnchor {
                anchor = value
                stop.pointee = true
            }
        }
        return anchor
    }

    /// The document's headings with text, with their IDs, as saving would
    /// write them.
    var headings: [Line] {
        MarkdownCodec.lines(fromMarkdown: markdown).filter(\.isTitledHeading)
    }

    /// Keeps each ID on one line. Splitting a heading leaves both halves
    /// with its ID, and pasting into one gives every pasted line the ID: of
    /// adjacent lines with the same ID, the first with any text keeps it.
    func keepHeadingAnchorsSingle(around editedRange: NSRange) {
        let string = storage.string as NSString
        var location = string.paragraphRange(for: editedRange).location
        let end = NSMaxRange(string.paragraphRange(for: editedRange))
        while location < end, location < storage.length {
            let line = lineRange(at: location)
            guard let anchor = headingAnchor(in: line) else {
                location = NSMaxRange(line)
                continue
            }
            // The run of lines with this ID.
            var run = [line]
            while run[0].location > 0, headingAnchor(in: lineRange(at: run[0].location - 1))?.id == anchor.id {
                run.insert(lineRange(at: run[0].location - 1), at: 0)
            }
            while NSMaxRange(run.last!) < storage.length, headingAnchor(in: lineRange(at: NSMaxRange(run.last!)))?.id == anchor.id {
                run.append(lineRange(at: NSMaxRange(run.last!)))
            }
            if run.count > 1 {
                let keeper = run.first { contentsRange(of: $0).length > 0 } ?? run[0]
                for other in run where other != keeper {
                    changeAttributes(in: other) {
                        storage.removeAttribute(.headingAnchor, range: other)
                    }
                }
            }
            location = NSMaxRange(run.last!)
        }
    }

    // MARK: - Typed IDs

    /// Whether `line` is a paragraph holding only an ID, as typed or pasted
    /// on the line above a heading.
    func anchorLine(_ line: NSRange) -> HeadingAnchor? {
        guard line.length > 0, listItem(at: line) == nil, storage.blockStyle(at: line.location) == .paragraph else {
            return nil
        }
        return HeadingAnchor(line: (storage.string as NSString).substring(with: contentsRange(of: line)))
    }

    /// Makes the ID on `idLine` the ID of the heading below, removing the
    /// line. Returns false, changing nothing, unless `idLine` holds only an
    /// ID and the next line is a heading.
    func convertAnchorLine(_ idLine: NSRange) -> Bool {
        guard let anchor = anchorLine(idLine), NSMaxRange(idLine) < storage.length,
              isHeadingLine(lineRange(at: NSMaxRange(idLine))) else { return false }
        replaceCharacters(in: idLine, with: NSAttributedString())
        give(anchor, toHeading: lineRange(at: idLine.location))
        return true
    }

    /// Makes a `{#x}` typed or pasted at the end of a heading its ID,
    /// removing it from the text. Returns false, changing nothing, unless
    /// `line` is a heading ending in one that `edit` touches.
    func convertTrailingAnchor(of line: NSRange, after edit: NSRange) -> Bool {
        guard isHeadingLine(line) else { return false }
        let contents = contentsRange(of: line)
        let text = (storage.string as NSString).substring(with: contents)
        guard let (rest, anchor) = HeadingAnchor.trailing(in: text) else { return false }
        let restLength = (rest as NSString).length
        let removed = NSRange(location: contents.location + restLength, length: contents.length - restLength)
        guard NSMaxRange(edit) > removed.location, edit.location <= NSMaxRange(removed) else { return false }
        replaceCharacters(in: removed, with: NSAttributedString())
        give(anchor, toHeading: lineRange(at: line.location))
        return true
    }

    /// Gives `heading` `anchor`, unless another heading, here or in the
    /// project's other files, has its ID, as when a heading is copied rather
    /// than moved. The copy is left without one, to get a new one when saved.
    private func give(_ anchor: HeadingAnchor, toHeading heading: NSRange) {
        let others = lineRanges(in: NSRange(location: 0, length: storage.length)).filter { $0 != heading && isTitledHeading($0) }
        guard !others.contains(where: { headingAnchor(in: $0)?.id == anchor.id }) else { return }
        let own = document?.fileURL?.standardizedFileURL
        if let project = document?.project,
           project.headingIDs().contains(where: { $0.url != own && $0.ids.contains(anchor.id) }) { return }
        changeAttributes(in: heading) {
            storage.addAttribute(.headingAnchor, value: anchor, range: heading)
        }
    }

    // MARK: - New IDs

    /// Gives every heading without an ID a new one, made by `scheme` from
    /// the file's name and the heading, written in `form`, and unlike any
    /// other in `taken` or the document. IDs already there aren't changed.
    /// With `onlyHeading`, only that heading (counting from 0) gets one.
    ///
    /// In the Formatted view this changes only attributes, which aren't
    /// undone, as the IDs aren't shown. In the Markdown view it inserts them,
    /// undoably.
    func addMissingHeadingIDs(scheme: HeadingIDScheme, form: HeadingAnchor.Form, fileName: String?, taken: Set<String>,
                              onlyHeading: Int? = nil) {
        guard !isPlainText else { return }
        var taken = taken.union(headings.compactMap(\.anchor?.id))
        func newAnchor(text: String, level: Int) -> HeadingAnchor {
            let id = scheme.makeID(text: text, level: level, fileName: fileName, taken: taken)
            taken.insert(id)
            return HeadingAnchor(id: id, form: form)
        }

        guard !isShowingMarkdown else {
            let markdown = storage.string
            var lines = MarkdownCodec.lines(fromMarkdown: markdown)
            for (number, index) in lines.indices.filter({ lines[$0].isTitledHeading }).enumerated()
            where lines[index].anchor == nil && (onlyHeading == nil || onlyHeading == number) {
                lines[index].anchor = newAnchor(text: lines[index].text, level: lines[index].style.rawValue)
            }
            replaceChangedText(with: MarkdownCodec.markdown(from: lines))
            return
        }
        guard storage.length > 0 else { return }
        storage.beginEditing()
        for (number, line) in lineRanges(in: NSRange(location: 0, length: storage.length)).filter(isTitledHeading).enumerated()
        where headingAnchor(in: line) == nil && (onlyHeading == nil || onlyHeading == number) {
            let anchor = newAnchor(text: inlineMarkdown(in: contentsRange(of: line)),
                                   level: storage.blockStyle(at: line.location).rawValue)
            storage.addAttribute(.headingAnchor, value: anchor, range: line)
        }
        storage.endEditing()
        updateForSelection()
    }

    /// Replaces the part of the text that differs from `text`, as one edit.
    private func replaceChangedText(with text: String) {
        let old = Array(storage.string.utf16)
        let new = Array(text.utf16)
        guard old != new else { return }
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        let replacement = String(decoding: new[prefix..<(new.count - suffix)], as: UTF16.self)
        replaceCharacters(in: NSRange(location: prefix, length: old.count - prefix - suffix),
                          with: NSAttributedString(string: replacement, attributes: Self.markdownAttributes))
    }
}
