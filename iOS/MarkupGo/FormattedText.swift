import MarkupCore
import UIKit

/// Converts Markdown to the text the editor shows and back.
///
/// Like the Mac editor, the text has no Markdown markers: a line's style is
/// an attribute on every character of it, and inline styles are attributes
/// on their characters. Only paragraphs, headings and code are formatted.
/// Every other line (list items, quotes, tables, front matter, comments over
/// several lines) is shown as its Markdown, in grey, and written back exactly
/// as read unless it was edited, when it is read again as Markdown.
enum FormattedText {
    /// Whether the editor formats `line`, rather than showing its Markdown.
    static func isFormatted(_ line: Line) -> Bool {
        line.list == nil && (line.style == .paragraph || line.style.isHeading || line.style == .code)
            && !line.text.contains("\n")
    }

    static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
        let lines = MarkdownCodec.lines(fromMarkdown: markdown)
        let text = NSMutableAttributedString()
        var blockFence: CodeFence?
        for (index, line) in lines.enumerated() {
            let terminator = index < lines.count - 1 ? "\n" : ""
            if !isFormatted(line) {
                let shown = line.style == .table || line.style == .frontMatter
                    ? line.text : MarkdownCodec.markdown(from: [line])
                let attributes = SourceStyle.attributes(SourceLine(line: line, shown: shown))
                text.append(NSAttributedString(string: shown + terminator, attributes: attributes))
            } else if line.style == .code {
                // The block's fence, if not plain, is on every character, so
                // that a following block can be told apart.
                if let fence = line.fence { blockFence = fence == CodeFence() ? nil : fence }
                var attributes = BlockStyle.code.attributes
                attributes[.codeFence] = blockFence
                text.append(NSAttributedString(string: line.text + terminator, attributes: attributes))
            } else {
                var attributes = line.style.attributes
                attributes[.headingAnchor] = line.anchor
                for span in InlineMarkdown.spans(in: line.text) {
                    text.append(NSAttributedString(string: span.text,
                                                   attributes: attributes.withInlineStyles(span.styles, link: span.link)))
                }
                text.append(NSAttributedString(string: terminator, attributes: attributes))
            }
        }
        text.applyAppearance(in: NSRange(location: 0, length: text.length))
        return text
    }

    static func markdown(from text: NSAttributedString) -> String {
        let string = text.string as NSString
        var ranges: [NSRange] = []
        var location = 0
        while location < string.length {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            ranges.append(line)
            location = NSMaxRange(line)
        }
        var lines: [Line] = []
        // Lines of Markdown source that were edited, read again together.
        var edited: [String] = []
        let readEdited = {
            if !edited.isEmpty { lines += MarkdownCodec.lines(fromMarkdown: edited.joined(separator: "\n")) }
            edited = []
        }
        var index = 0
        while index < ranges.count {
            let range = ranges[index]
            let contents = contentsRange(of: range, in: string)
            if let source = text.sourceLine(at: range.location) {
                // A line read over several lines is shown on several.
                var texts: [String] = []
                while index < ranges.count, text.sourceLine(at: ranges[index].location) === source {
                    texts.append(string.substring(with: contentsRange(of: ranges[index], in: string)))
                    index += 1
                }
                if let line = source.line, texts.joined(separator: "\n") == source.shown {
                    readEdited()
                    lines.append(line)
                } else {
                    edited += texts
                }
                continue
            }
            readEdited()
            let style = text.blockStyle(at: range.location)
            if style == .code {
                let fence = text.attribute(.codeFence, at: range.location, effectiveRange: nil) as? CodeFence
                let startsBlock = lines.last?.style != .code || range.location == 0
                    || text.sourceLine(at: range.location - 1) != nil
                    || text.attribute(.codeFence, at: range.location - 1, effectiveRange: nil) as? CodeFence != fence
                lines.append(Line(style: .code, text: string.substring(with: contents),
                                  fence: startsBlock ? fence ?? CodeFence() : nil))
            } else {
                // A heading whose text has all gone is an empty line.
                let isEmpty = contents.length == 0
                lines.append(Line(style: isEmpty ? .paragraph : style, text: inlineMarkdown(in: contents, of: text),
                                  anchor: isEmpty || !style.isHeading ? nil
                                      : text.attribute(.headingAnchor, at: range.location, effectiveRange: nil) as? HeadingAnchor))
            }
            index += 1
        }
        readEdited()
        // A final newline is followed by an empty last line.
        if string.length > 0, string.character(at: string.length - 1) == 0x0A {
            lines.append(Line(style: .paragraph, text: ""))
        }
        return MarkdownCodec.markdown(from: lines)
    }

    /// `line` without its newline, if it has one.
    static func contentsRange(of line: NSRange, in string: NSString) -> NSRange {
        let hasNewline = line.length > 0 && string.character(at: NSMaxRange(line) - 1) == 0x0A
        return NSRange(location: line.location, length: line.length - (hasNewline ? 1 : 0))
    }

    /// The Markdown for `range`, within one line: its text with inline
    /// styles and links as their delimiters.
    static func inlineMarkdown(in range: NSRange, of text: NSAttributedString) -> String {
        var spans: [InlineSpan] = []
        let string = text.string as NSString
        text.enumerateAttributes(in: range) { attributes, run, _ in
            let styles = Set(InlineStyle.allCases.filter { attributes[$0.key] != nil })
            let link = attributes[.markdownLink] as? String
            let runText = string.substring(with: run)
            if let last = spans.last, last.styles == styles, last.link == link {
                spans[spans.count - 1].text += runText
            } else {
                spans.append(InlineSpan(runText, styles: styles, link: link))
            }
        }
        return InlineMarkdown.markdown(for: spans)
    }
}
