import AppKit
import MarkupCore

extension EditorWindowController {
    func load(markdown: String) {
        let lines = MarkdownCodec.lines(fromMarkdown: markdown)
        let text = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let terminator = index < lines.count - 1 ? "\n" : ""
            if let item = line.list {
                text.append(item.markerString)
                text.append(NSAttributedString(string: line.text + terminator, attributes: item.lineAttributes))
            } else {
                text.append(NSAttributedString(string: line.text + terminator, attributes: line.style.attributes))
            }
        }
        storage.setAttributedString(text)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        updateForSelection()
    }

    var markdown: String {
        let string = storage.string as NSString
        var lines: [Line] = []
        var location = 0
        repeat {
            let line = lineRange(at: location)
            let contents = contentsRange(of: line)
            if let item = listItem(at: line) {
                let text = string.substring(with: NSRange(location: contents.location + 1, length: contents.length - 1))
                lines.append(Line(style: .paragraph, text: text, list: item))
            } else {
                let style = line.length > 0 ? storage.blockStyle(at: line.location) : .paragraph
                lines.append(Line(style: style, text: string.substring(with: contents)))
            }
            location = NSMaxRange(line)
        } while location < string.length
        // A trailing newline is followed by an empty last line.
        if string.length > 0, string.character(at: string.length - 1) == 0x0A {
            lines.append(Line(style: .paragraph, text: ""))
        }
        return MarkdownCodec.markdown(from: lines)
    }

    /// The text of `range` for the pasteboard, with each list marker written
    /// as its Markdown, so pasting the text back recreates the list.
    func plainText(for range: NSRange) -> String {
        let string = storage.string as NSString
        var text = ""
        storage.enumerateAttribute(.listMarker, in: range) { value, run, _ in
            guard let raw = value as? Int, let marker = ListMarker(rawValue: raw) else {
                text += string.substring(with: run)
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
