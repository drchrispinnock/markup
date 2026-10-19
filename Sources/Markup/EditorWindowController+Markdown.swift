import AppKit
import MarkupCore

extension EditorWindowController {
    func load(markdown: String) {
        storage.setAttributedString(Self.formattedText(fromMarkdown: markdown, imageFolders: imageFolders))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        updateForSelection()
    }

    /// The folders an image's path is looked up in: the document's own
    /// folder, then the images directory.
    var imageFolders: [URL] {
        [markdownDocument?.fileURL?.deletingLastPathComponent(), settings.imagesDirectory].compactMap { $0 }
    }

    /// Markdown as the editor shows it: markers turned into styles, list
    /// markers and images. Used for editing and printing.
    static func formattedText(fromMarkdown markdown: String, imageFolders: [URL]) -> NSAttributedString {
        let lines = MarkdownCodec.lines(fromMarkdown: markdown)
        let text = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let terminator = index < lines.count - 1 ? "\n" : ""
            if let item = line.list {
                text.append(item.markerString)
                text.append(inlineText(line.text + terminator, attributes: item.lineAttributes, imageFolders: imageFolders))
            } else {
                text.append(inlineText(line.text + terminator, attributes: line.style.attributes, imageFolders: imageFolders))
            }
        }
        return text
    }

    /// `text` with its images shown.
    private static func inlineText(_ text: String, attributes: [NSAttributedString.Key: Any],
                                   imageFolders: [URL]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        for match in MarkdownImage.images(in: text).reversed() {
            let range = NSRange(location: match.range.lowerBound, length: match.range.count)
            let markdown = (text as NSString).substring(with: range)
            result.replaceCharacters(in: range, with: match.image.attachmentString(
                markdown: markdown, attributes: attributes, folders: imageFolders))
        }
        return result
    }

    var markdown: String {
        guard !isShowingMarkdown else { return storage.string }
        let string = storage.string as NSString
        var lines: [Line] = []
        var location = 0
        repeat {
            let line = lineRange(at: location)
            let contents = contentsRange(of: line)
            if let item = listItem(at: line) {
                let text = markdownText(in: NSRange(location: contents.location + 1, length: contents.length - 1))
                lines.append(Line(style: .paragraph, text: text, list: item))
            } else {
                let style = line.length > 0 ? storage.blockStyle(at: line.location) : .paragraph
                lines.append(Line(style: style, text: markdownText(in: contents)))
            }
            location = NSMaxRange(line)
        } while location < string.length
        // A trailing newline is followed by an empty last line.
        if string.length > 0, string.character(at: string.length - 1) == 0x0A {
            lines.append(Line(style: .paragraph, text: ""))
        }
        return MarkdownCodec.markdown(from: lines)
    }

    /// The text of `range` with each image written as its Markdown.
    private func markdownText(in range: NSRange) -> String {
        let string = storage.string as NSString
        var text = ""
        storage.enumerateAttribute(.markdownImage, in: range) { value, run, _ in
            // Adjacent copies of the same image form one run.
            text += (value as? String).map { String(repeating: $0, count: run.length) } ?? string.substring(with: run)
        }
        return text
    }

    /// The text of `range` for the pasteboard, with each list marker and image
    /// written as its Markdown, so pasting the text back recreates them.
    func plainText(for range: NSRange) -> String {
        var text = ""
        storage.enumerateAttribute(.listMarker, in: range) { value, run, _ in
            guard let raw = value as? Int, let marker = ListMarker(rawValue: raw) else {
                text += markdownText(in: run)
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
