import AppKit
import MarkupCore

extension EditorViewController {
    /// Shows `markdown` formatted, or as it is in a plain text document.
    func load(markdown: String) {
        storage.setAttributedString(isPlainText ? NSAttributedString(string: markdown, attributes: Self.markdownAttributes)
                                                : Self.formattedText(fromMarkdown: markdown, imageFolders: imageFolders))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        updateForSelection()
        resetLinkCheck()
    }

    /// The folders an image's path is looked up in (`Settings.imageFolders`).
    var imageFolders: [URL] {
        settings.imageFolders(forDocumentAt: document?.fileURL)
    }

    /// Markdown as the editor shows it: markers turned into styles, list
    /// markers and images. Used for editing and printing.
    static func formattedText(fromMarkdown markdown: String, imageFolders: [URL]) -> NSAttributedString {
        let lines = MarkdownCodec.lines(fromMarkdown: markdown)
        let text = NSMutableAttributedString()
        var blockFence: CodeFence?
        var tableLines: [String] = []
        for (index, line) in lines.enumerated() {
            // A table is shown as a grid of cells once all its lines are in.
            if line.style == .table {
                tableLines.append(line.text)
                if index == lines.count - 1 || lines[index + 1].style != .table,
                   let table = MarkdownTable.table(from: tableLines) {
                    text.append(tableText(table, imageFolders: imageFolders))
                    tableLines = []
                }
                continue
            }
            let terminator = index < lines.count - 1 ? "\n" : ""
            if let item = line.list {
                text.append(item.markerString)
                text.append(inlineText(line.text + terminator, attributes: item.lineAttributes, imageFolders: imageFolders))
            } else if line.style == .code {
                // Code is kept as typed. Its block's fence, if not plain,
                // is on every character, so later lines can be told apart
                // from the next block.
                if let fence = line.fence { blockFence = fence == CodeFence() ? nil : fence }
                var attributes = BlockStyle.code.attributes
                attributes[.codeFence] = blockFence
                text.append(NSAttributedString(string: line.text + terminator, attributes: attributes))
            } else {
                var attributes = line.style.attributes
                attributes[.headingAnchor] = line.anchor
                // A line of only comments is hidden altogether.
                let comments = HTMLComment.ranges(in: line.text)
                if !comments.isEmpty, comments.reduce(0, { $0 + $1.count }) == line.text.utf16.count {
                    attributes[.paragraphStyle] = HTMLComment.hiddenLineStyle
                }
                text.append(inlineText(line.text + terminator, attributes: attributes, imageFolders: imageFolders))
            }
        }
        return text
    }

    /// One line's text (and newline, if any), with its emphasis and images
    /// shown, and comments hidden.
    static func inlineText(_ text: String, attributes: [NSAttributedString.Key: Any],
                                   imageFolders: [URL]) -> NSAttributedString {
        let hasNewline = text.hasSuffix("\n")
        let result = NSMutableAttributedString()
        for span in InlineMarkdown.spans(in: hasNewline ? String(text.dropLast()) : text) {
            let spanText = NSMutableAttributedString(
                string: span.text, attributes: attributes.withInlineStyles(span.styles, link: span.link))
            // Tags first, since they are written as comments, then
            // comments: an image inside one is part of it.
            let tags = MarkupTag.tags(in: span.text)
            let comments = HTMLComment.ranges(in: span.text).filter { comment in !tags.contains { $0.range.overlaps(comment) } }
            let images = MarkdownImage.images(in: span.text).filter { image in
                !tags.contains { $0.range.overlaps(image.range) } && !comments.contains { $0.overlaps(image.range) }
            }
            let wholes = tags.map { ($0.range, Whole.tag($0.tag)) } + comments.map { ($0, Whole.comment) }
                + images.map { ($0.range, Whole.image($0.image)) }
            for (whole, kind) in wholes.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
                let range = NSRange(location: whole.lowerBound, length: whole.count)
                let markdown = (span.text as NSString).substring(with: range)
                let attributes = spanText.attributes(at: range.location, effectiveRange: nil)
                switch kind {
                case .tag(let tag):
                    spanText.replaceCharacters(in: range, with: tag.attachmentString(attributes: attributes))
                case .comment:
                    spanText.replaceCharacters(in: range, with: HTMLComment.attachmentString(markdown: markdown, attributes: attributes))
                case .image(let image):
                    spanText.replaceCharacters(in: range, with: image.attachmentString(markdown: markdown, attributes: attributes,
                                                                                       folders: imageFolders))
                }
            }
            result.append(spanText)
        }
        if hasNewline {
            result.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        return result
    }

    /// Something in a line's Markdown shown as one attachment character.
    private enum Whole {
        case tag(MarkupTag)
        case comment
        case image(MarkdownImage)
    }

    var markdown: String {
        guard !isShowingMarkdown else { return storage.string }
        let string = storage.string as NSString
        var lines: [Line] = []
        var location = 0
        repeat {
            let line = lineRange(at: location)
            let contents = contentsRange(of: line)
            if isTableLine(line) {
                let cells = tableLines(around: line)
                // Tables need a blank line between them.
                if lines.last?.style == .table { lines.append(Line(style: .paragraph, text: "")) }
                lines += MarkdownTable.lines(for: markdownTable(of: cells)).map { Line(style: .table, text: $0) }
                location = NSMaxRange(cells.last!)
                continue
            }
            if let item = listItem(at: line) {
                let text = inlineMarkdown(in: NSRange(location: contents.location + 1, length: contents.length - 1))
                lines.append(Line(style: .paragraph, text: text, list: item))
            } else if line.length > 0, storage.blockStyle(at: line.location) == .code {
                // A block starts after a line that isn't code, or where the
                // fence changes.
                let fence = storage.attribute(.codeFence, at: line.location, effectiveRange: nil) as? CodeFence
                let startsBlock = lines.last?.style != .code || line.location == 0
                    || storage.attribute(.codeFence, at: line.location - 1, effectiveRange: nil) as? CodeFence != fence
                lines.append(Line(style: .code, text: markdownText(in: contents),
                                  fence: startsBlock ? fence ?? CodeFence() : nil))
            } else {
                // A heading whose text has all been deleted is gone, ID and
                // all, rather than left as a bare "##".
                let style = contents.length > 0 ? storage.blockStyle(at: line.location) : .paragraph
                lines.append(Line(style: style, text: inlineMarkdown(in: contents),
                                  anchor: contents.length > 0 ? headingAnchor(in: line) : nil))
            }
            location = NSMaxRange(line)
        } while location < string.length
        // A trailing newline is followed by an empty last line.
        if string.length > 0, string.character(at: string.length - 1) == 0x0A {
            lines.append(Line(style: .paragraph, text: ""))
        }
        return MarkdownCodec.markdown(from: lines)
    }

    /// The text of `range` with each tag, image and comment written as its
    /// Markdown.
    private func markdownText(in range: NSRange) -> String {
        let string = storage.string as NSString
        var text = ""
        storage.enumerateAttributes(in: range) { attributes, run, _ in
            // Adjacent copies of the same tag, image or comment form one run.
            let markdown = (attributes[.markupTag] as? MarkupTag)?.markdown
                ?? (attributes[.markdownImage] ?? attributes[.markdownComment]) as? String
            text += markdown.map { String(repeating: $0, count: run.length) } ?? string.substring(with: run)
        }
        return text
    }

    /// The Markdown for `range`, which is within one line: inline styles as
    /// their delimiters, images as written.
    func inlineMarkdown(in range: NSRange) -> String {
        var spans: [InlineSpan] = []
        storage.enumerateAttributes(in: range) { attributes, run, _ in
            let styles = Set(InlineStyle.allCases.filter { attributes[$0.key] != nil })
            let link = attributes[.markdownLink] as? String
            let text = markdownText(in: run)
            if let last = spans.last, last.styles == styles, last.link == link {
                spans[spans.count - 1].text += text
            } else {
                spans.append(InlineSpan(text, styles: styles, link: link))
            }
        }
        return InlineMarkdown.markdown(for: spans)
    }

    /// The text of `range` for the pasteboard, with each list marker, image
    /// and inline style written as its Markdown, so pasting the text back
    /// recreates them. A table the range goes beyond one cell of is written
    /// whole, as a Markdown table.
    func plainText(for range: NSRange) -> String {
        guard !isShowingMarkdown else { return (storage.string as NSString).substring(with: range) }
        let touched = lineRanges(in: range).filter(isTableLine)
        if let cell = touched.first, touched.count > 1 || NSMaxRange(range) > NSMaxRange(contentsRange(of: cell)) {
            var text = ""
            var location = range.location
            while location < NSMaxRange(range) {
                let line = lineRange(at: location)
                if isTableLine(line) {
                    let cells = tableLines(around: line)
                    let end = NSMaxRange(cells.last!)
                    text += MarkdownTable.lines(for: markdownTable(of: cells)).joined(separator: "\n")
                    if NSMaxRange(range) >= end { text += "\n" }
                    location = end
                } else {
                    let end = min(NSMaxRange(line), NSMaxRange(range))
                    text += plainText(for: NSRange(location: location, length: end - location))
                    location = end
                }
            }
            return text
        }
        var text = ""
        storage.enumerateAttribute(.listMarker, in: range) { value, run, _ in
            guard let raw = value as? Int, let marker = ListMarker(rawValue: raw) else {
                // Inline styles are written line by line. Code is as typed.
                let string = storage.string as NSString
                var location = run.location
                while location < NSMaxRange(run) {
                    let newline = string.range(of: "\n", range: NSRange(location: location, length: NSMaxRange(run) - location))
                    let end = newline.location == NSNotFound ? NSMaxRange(run) : newline.location
                    let segment = NSRange(location: location, length: end - location)
                    let line = lineRange(at: location)
                    if segment == contentsRange(of: line), isTitledHeading(line) {
                        // A whole heading is copied as one, with its ID, so
                        // that moving it keeps the links to it.
                        text += MarkdownCodec.markdown(from: [Line(style: storage.blockStyle(at: location),
                                                                   text: inlineMarkdown(in: segment),
                                                                   anchor: headingAnchor(in: line))])
                    } else {
                        text += segment.length > 0 && storage.blockStyle(at: location) == .code
                            ? markdownText(in: segment) : inlineMarkdown(in: segment)
                    }
                    if newline.location != NSNotFound { text += "\n" }
                    location = newline.location == NSNotFound ? end : NSMaxRange(newline)
                }
                return
            }
            for index in run.location..<NSMaxRange(run) {
                let level = storage.attribute(.listLevel, at: index, effectiveRange: nil) as? Int ?? 0
                text += ListItem(level: level, marker: marker).markdown
            }
        }
        return text
    }
}
