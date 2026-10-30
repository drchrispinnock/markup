import AppKit
import MarkupCore

/// Code blocks: lines in the Code style, saved between ``` fences.
extension EditorViewController {
    /// Return in a code block. On a line holding just a fence ("```", or
    /// "```swift") it turns the line into an empty code line instead. On an
    /// empty last line of a block it ends the block, making the line a
    /// paragraph. At the end of any other code line it starts another code
    /// line in the same block.
    func insertNewlineInCode() -> Bool {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let line = lineRange(at: selection.location)
        let contents = contentsRange(of: line)
        guard selection.location == NSMaxRange(contents) else { return false }
        let style = line.length > 0 ? storage.blockStyle(at: line.location) : styleAtCaretForEmptyLine

        if style != .code, listItem(at: line) == nil,
           let fence = CodeFence(line: (storage.string as NSString).substring(with: contents)) {
            replaceCharacters(in: contents, with: NSAttributedString())
            emptyLineStyle = (line.location, .code)
            emptyLineFence = fence == CodeFence() ? nil : fence
            let codeLine = lineRange(at: line.location)
            if codeLine.length > 0 {
                changeAttributes(in: codeLine) {
                    storage.addAttributes(BlockStyle.code.attributes, range: codeLine)
                    for inlineStyle in InlineStyle.allCases {
                        storage.removeAttribute(inlineStyle.key, range: codeLine)
                    }
                    if fence != CodeFence() {
                        storage.addAttribute(.codeFence, value: fence, range: codeLine)
                    }
                    storage.applyInlineStyles(in: codeLine)
                }
            }
            textView.setSelectedRange(NSRange(location: line.location, length: 0))
            updateForSelection()
            return true
        }

        guard style == .code else { return false }
        let fence = line.length > 0 ? storage.attribute(.codeFence, at: line.location, effectiveRange: nil) as? CodeFence
            : emptyLineFence
        guard contents.length == 0 else {
            // The new line, if it is the empty last line, has no characters
            // to carry the style, so remember it.
            textView.insertNewline(nil)
            let caret = textView.selectedRange().location
            if lineRange(at: caret).length == 0 {
                emptyLineStyle = (caret, .code)
                emptyLineFence = fence
            }
            updateForSelection()
            return true
        }
        let next = NSMaxRange(line)
        let isLastOfBlock = next >= storage.length || storage.blockStyle(at: next) != .code
            || storage.attribute(.codeFence, at: next, effectiveRange: nil) as? CodeFence != fence
        guard isLastOfBlock else { return false }
        if line.length > 0 {
            changeAttributes(in: line) {
                storage.addAttributes(BlockStyle.paragraph.attributes, range: line)
                storage.removeAttribute(.codeFence, range: line)
                storage.applyInlineStyles(in: line)
            }
        }
        emptyLineStyle = (line.location, .paragraph)
        updateForSelection()
        return true
    }

    /// Pastes `text`, Markdown holding fenced code blocks, at the selection:
    /// the text around each block as if it were typed, so its shortcuts
    /// convert it, and each block as code lines kept as written, which
    /// typing would convert. Into a code line, one block goes in as its
    /// lines. Returns false, to paste as usual, for text with no blocks.
    func pasteCodeBlocks(_ text: String) -> Bool {
        guard !isShowingMarkdown, !isPlainText else { return false }
        let pieces = MarkdownCodec.pieces(of: text)
        guard pieces.contains(where: { if case .code = $0 { true } else { false } }) else { return false }
        let line = lineRange(at: textView.selectedRange().location)
        if line.length > 0 ? storage.blockStyle(at: line.location) == .code : styleAtCaretForEmptyLine == .code {
            guard pieces.count == 1, case .code(let lines, _) = pieces[0] else { return false }
            textView.insertText(lines.joined(separator: "\n"), replacementRange: textView.selectedRange())
            return true
        }
        for (index, piece) in pieces.enumerated() {
            let range = textView.selectedRange()
            switch piece {
            case .text(let text):
                if !text.isEmpty || range.length > 0 { textView.insertText(text, replacementRange: range) }
            case .code(let lines, let fence):
                // A block is on lines of its own: it ends the line before
                // it, and the text after the caret, or more pasted text,
                // goes on the line after it.
                let caretLine = lineRange(at: range.location)
                var attributes = BlockStyle.code.attributes
                if fence != CodeFence() { attributes[.codeFence] = fence }
                let code = NSMutableAttributedString(attributedString: MarkupTag.codeText(lines.joined(separator: "\n"),
                                                                                          attributes: attributes))
                if index < pieces.count - 1 || NSMaxRange(range) < NSMaxRange(contentsRange(of: caretLine)) {
                    code.append(NSAttributedString(string: "\n", attributes: attributes))
                }
                if range.location > caretLine.location {
                    code.insert(NSAttributedString(string: "\n", attributes: textView.typingAttributes), at: 0)
                }
                replaceCharacters(in: range, with: code)
                textView.setSelectedRange(NSRange(location: range.location + code.length, length: 0))
            }
        }
        undoManager?.setActionName("Paste")
        return true
    }

    /// The style an empty last line would be typed in.
    var styleAtCaretForEmptyLine: BlockStyle {
        (textView.typingAttributes[.blockStyle] as? Int).flatMap(BlockStyle.init) ?? .paragraph
    }

    /// View > Reload Images: reads every image in the document from disk
    /// again, for when the files have changed.
    @objc func reloadImages(_ sender: Any?) {
        guard !isShowingMarkdown else { return }
        let folders = imageFolders
        storage.beginEditing()
        storage.enumerateAttribute(.markdownImage, in: NSRange(location: 0, length: storage.length)) { value, run, _ in
            guard let markdown = value as? String else { return }
            for index in run.location..<NSMaxRange(run) {
                guard let image = MarkdownImage.image(written: markdown) else { continue }
                let attributes = storage.attributes(at: index, effectiveRange: nil)
                let fresh = image.attachmentString(markdown: markdown, attributes: attributes, folders: folders)
                storage.addAttribute(.attachment, value: fresh.attribute(.attachment, at: 0, effectiveRange: nil)!,
                                     range: NSRange(location: index, length: 1))
            }
        }
        storage.endEditing()
    }
}

/// Shades the lines of code blocks across the full width of the text.
final class EditorLayoutManager: NSLayoutManager {
    /// Whether an image alone on its line is centred (`Settings.centersImages`).
    /// `ImageAttachmentCell` reads it.
    var centersImages = false

    /// The bar beside a blockquote's lines.
    static let quoteBarColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.3) : NSColor(white: 0, alpha: 0.2)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage else { return }
        // Quotes have a bar down their left, through all their lines.
        Self.quoteBarColor.setFill()
        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, container, glyphRange, _ in
            let index = self.characterIndexForGlyph(at: glyphRange.location)
            guard index < textStorage.length, textStorage.blockStyle(at: index) == .quote else { return }
            NSRect(x: origin.x + container.lineFragmentPadding + 2, y: rect.minY + origin.y, width: 3, height: rect.height).fill()
        }
        InlineStyle.codeBackground.setFill()
        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, _, container, glyphRange, _ in
            let index = self.characterIndexForGlyph(at: glyphRange.location)
            guard index < textStorage.length, textStorage.blockStyle(at: index) == .code else { return }
            NSRect(x: origin.x, y: rect.minY + origin.y, width: container.size.width, height: rect.height).fill()
        }
        // An empty last line in a code block is the extra line fragment.
        if let container = extraLineFragmentTextContainer, textStorage.length > 0,
           textStorage.blockStyle(at: textStorage.length - 1) == .code,
           (textStorage.string as NSString).character(at: textStorage.length - 1) == 0x0A {
            let rect = extraLineFragmentRect
            NSRect(x: origin.x, y: rect.minY + origin.y, width: container.size.width, height: rect.height).fill()
        }
    }
}
