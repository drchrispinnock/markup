import AppKit
import MarkupCore

extension EditorViewController {
    /// Shows `markdown` formatted, or as it is in a plain text document.
    /// The formatted view keeps the front matter aside, and shows the badge.
    func load(markdown: String) {
        frontMatter = isPlainText ? nil : MarkdownCodec.frontMatter(in: markdown)?.frontMatter
        updateFrontMatterBadge()
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

    /// Lines of Leanpub markup that the formatted view hides, as it hides a
    /// line of only comments.
    static let hiddenLines: Set<String> = ["{begin-hanging-paragraphs}", "{end-hanging-paragraphs}"]

    /// Markdown as the editor shows it: markers turned into styles, list
    /// markers and images, and front matter left out. Used for editing and
    /// printing.
    static func formattedText(fromMarkdown markdown: String, imageFolders: [URL]) -> NSAttributedString {
        let lines = MarkdownCodec.lines(fromMarkdown: markdown).filter { $0.style != .frontMatter }
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
            } else if line.style == .paragraph, line.list == nil, Self.hiddenLines.contains(line.text) {
                // Kept as written, like a comment, and hidden.
                var attributes = line.style.attributes
                attributes[.paragraphStyle] = HTMLComment.hiddenLineStyle
                text.append(HTMLComment.attachmentString(markdown: line.text, attributes: attributes))
                text.append(NSAttributedString(string: terminator, attributes: attributes))
            } else {
                var attributes = line.style.attributes
                attributes[.headingAnchor] = line.anchor
                // A line of only comments, and <p> and </p>, is hidden
                // altogether.
                let comments = HTMLComment.ranges(in: line.text)
                let hidden = comments + HTMLTag.tags(in: line.text).filter { tag in
                    tag.tag.isParagraph && !comments.contains { $0.overlaps(tag.range) }
                }.map(\.range)
                if !hidden.isEmpty, hidden.reduce(0, { $0 + $1.count }) == line.text.utf16.count {
                    attributes[.paragraphStyle] = HTMLComment.hiddenLineStyle
                }
                text.append(inlineText(line.text + terminator, attributes: attributes, imageFolders: imageFolders))
            }
        }
        return text
    }

    /// One line's text (and newline, if any), with its emphasis, images and
    /// HTML tags shown, and comments hidden.
    static func inlineText(_ text: String, attributes: [NSAttributedString.Key: Any],
                                   imageFolders: [URL]) -> NSAttributedString {
        let hasNewline = text.hasSuffix("\n")
        let result = NSMutableAttributedString()
        let spans = InlineMarkdown.spans(in: hasNewline ? String(text.dropLast()) : text)
        for (spanIndex, span) in spans.enumerated() {
            let spanText = NSMutableAttributedString(
                string: span.text, attributes: attributes.withInlineStyles(span.styles, link: span.link))
            // Tags first, since they are written as comments, then
            // comments: an image inside one is part of it. Then HTML tags,
            // whose attributes may hold what looks like an image.
            let tags = MarkupTag.tags(in: span.text)
            let comments = HTMLComment.ranges(in: span.text).filter { comment in !tags.contains { $0.range.overlaps(comment) } }
            let htmlTags = HTMLTag.tags(in: span.text).filter { tag in
                !tags.contains { $0.range.overlaps(tag.range) } && !comments.contains { $0.overlaps(tag.range) }
            }
            let images = MarkdownImage.images(in: span.text).filter { image in
                !tags.contains { $0.range.overlaps(image.range) } && !comments.contains { $0.overlaps(image.range) }
                    && !htmlTags.contains { $0.range.overlaps(image.range) }
            }
            let wholes = tags.map { ($0.range, Whole.tag($0.tag)) } + comments.map { ($0, Whole.comment) }
                + htmlTags.map { ($0.range, Whole.html($0.tag)) } + images.map { ($0.range, Whole.image($0.image)) }
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
                case .html(let tag):
                    // A <br> with only spaces after it ends the line.
                    let rest = (span.text as NSString).substring(from: NSMaxRange(range))
                    let endsLine = spanIndex == spans.count - 1 && rest.allSatisfy { $0 == " " }
                    spanText.replaceCharacters(in: range, with: tag.attachmentString(markdown: markdown, attributes: attributes,
                                                                                     folders: imageFolders, endsLine: endsLine))
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
        case html(HTMLTag)
    }

    var markdown: String {
        guard !isShowingMarkdown else { return storage.string }
        let string = storage.string as NSString
        var lines = markdownLines(from: 0, to: string.length)
        // A trailing newline is followed by an empty last line.
        if string.length > 0, string.character(at: string.length - 1) == 0x0A {
            lines.append(Line(style: .paragraph, text: ""))
        }
        let body = MarkdownCodec.markdown(from: lines)
        guard let frontMatter else { return body }
        // Front matter that ended the file needs a newline before new text.
        return frontMatter + (frontMatter.hasSuffix("\n") || body.isEmpty ? "" : "\n") + body
    }

    /// The Markdown lines of the text's lines from the one at `start` to the
    /// one before `end`, or the one at `start` if that is `end`.
    func markdownLines(from start: Int, to end: Int) -> [Line] {
        var lines: [Line] = []
        var location = start
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
            if var item = listItem(at: line) {
                if item.marker == .numbered { item.number = storage.listNumber(atLineStart: line.location) }
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
                // all, rather than left as a bare "##". An empty quote line
                // stays one.
                let blockStyle = line.length > 0 ? storage.blockStyle(at: line.location) : .paragraph
                let style = contents.length > 0 || blockStyle == .quote ? blockStyle : .paragraph
                lines.append(Line(style: style, text: inlineMarkdown(in: contents),
                                  anchor: contents.length > 0 ? headingAnchor(in: line) : nil))
            }
            location = NSMaxRange(line)
        } while location < end
        return lines
    }

    /// The text of `range` with each tag, image, comment and HTML tag written
    /// as its Markdown.
    private func markdownText(in range: NSRange) -> String {
        let string = storage.string as NSString
        var text = ""
        storage.enumerateAttributes(in: range) { attributes, run, _ in
            // Adjacent copies of the same tag, image or comment form one run.
            let markdown = (attributes[.markupTag] as? MarkupTag)?.markdown
                ?? (attributes[.markdownImage] ?? attributes[.markdownComment] ?? attributes[.markdownHTML]) as? String
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
        // Whole code lines, written as a block between fences once the
        // block ends, and whether a newline followed the last.
        var codeLines: [Line] = []
        var codeEndsWithNewline = false
        func writeCode() {
            guard !codeLines.isEmpty else { return }
            text += MarkdownCodec.markdown(from: codeLines) + (codeEndsWithNewline ? "\n" : "")
            codeLines = []
        }
        storage.enumerateAttribute(.listMarker, in: range) { value, run, _ in
            guard value != nil else {
                // Inline styles are written line by line. Part of a code
                // line is as typed.
                let string = storage.string as NSString
                var location = run.location
                while location < NSMaxRange(run) {
                    let newline = string.range(of: "\n", range: NSRange(location: location, length: NSMaxRange(run) - location))
                    let end = newline.location == NSNotFound ? NSMaxRange(run) : newline.location
                    let segment = NSRange(location: location, length: end - location)
                    let line = lineRange(at: location)
                    if segment == contentsRange(of: line), line.length > 0, storage.blockStyle(at: line.location) == .code {
                        // Whole code lines are copied as a block, so they
                        // paste back as one. A change of fence starts
                        // another.
                        let fence = storage.attribute(.codeFence, at: line.location, effectiveRange: nil) as? CodeFence
                        let previousFence = line.location > 0
                            ? storage.attribute(.codeFence, at: line.location - 1, effectiveRange: nil) as? CodeFence : nil
                        let startsBlock = codeLines.isEmpty || previousFence != fence
                        codeLines.append(Line(style: .code, text: markdownText(in: segment),
                                              fence: startsBlock ? fence ?? CodeFence() : nil))
                        codeEndsWithNewline = newline.location != NSNotFound
                        location = newline.location == NSNotFound ? end : NSMaxRange(newline)
                        continue
                    }
                    writeCode()
                    if segment == contentsRange(of: line), isTitledHeading(line) {
                        // A whole heading is copied as one, with its ID, so
                        // that moving it keeps the links to it.
                        text += MarkdownCodec.markdown(from: [Line(style: storage.blockStyle(at: location),
                                                                   text: inlineMarkdown(in: segment),
                                                                   anchor: headingAnchor(in: line))])
                    } else if segment == contentsRange(of: line), line.length > 0, storage.blockStyle(at: location) == .quote {
                        // So is a whole quote line, after its "> ".
                        text += MarkdownCodec.markdown(from: [Line(style: .quote, text: inlineMarkdown(in: segment))])
                    } else {
                        text += segment.length > 0 && storage.blockStyle(at: location) == .code
                            ? markdownText(in: segment) : inlineMarkdown(in: segment)
                    }
                    if newline.location != NSNotFound { text += "\n" }
                    location = newline.location == NSNotFound ? end : NSMaxRange(newline)
                }
                return
            }
            writeCode()
            for index in run.location..<NSMaxRange(run) {
                text += markdownPrefix(ofListLineAt: index)
            }
        }
        writeCode()
        return text
    }
}
