import AppKit
import MarkupCore

extension NSAttributedString.Key {
    /// The Markdown of an inline image, exactly as written, on the attachment
    /// character that shows it. Saving and copying write it back unchanged.
    static let markdownImage = NSAttributedString.Key("MarkupMarkdownImage")
}

extension MarkdownImage {
    /// The attachment character that shows the image. `markdown` is the
    /// image's Markdown as written, and `attributes` are the line's.
    @MainActor
    func attachmentString(markdown: String, attributes: [NSAttributedString.Key: Any],
                          folders: [URL]) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let url = fileURL(in: folders)
        let picture = url.flatMap(NSImage.init(contentsOf:))
        attachment.attachmentCell = ImageAttachmentCell(picture: picture, code: picture == nil ? includedText(at: url) : nil,
                                                        path: path)
        var attributes = attributes
        attributes[.attachment] = attachment
        attributes[.markdownImage] = markdown
        return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
    }

    /// The text of a file that isn't a picture, as Leanpub includes a
    /// resource such as a configuration file in the book as code; nil if
    /// it isn't text.
    func includedText(in folders: [URL]) -> String? {
        let url = fileURL(in: folders)
        return url.flatMap(NSImage.init(contentsOf:)) == nil ? includedText(at: url) : nil
    }

    private func includedText(at url: URL?) -> String? {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    /// The image's file: the path looked up in each folder in turn. A path
    /// starting with "/", such as Jekyll's "/assets/a.png" from the website's
    /// root, is looked up without it, and failing that is the file at that
    /// full path, as Insert Image writes for one in none of the folders. Nil
    /// for web addresses, "//" ones included, and for files that can't be
    /// found.
    func fileURL(in folders: [URL]) -> URL? {
        guard !path.isEmpty, !path.contains("://"), !path.hasPrefix("//") else { return nil }
        // Markdown paths are URLs, so spaces may be written as %20.
        let paths = [path, path.removingPercentEncoding].compactMap { $0 }
        let relative = paths.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 }
        let candidates = folders.flatMap { folder in relative.map { folder.appendingPathComponent($0) } }
            + paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }
}

/// Draws an image at its actual size, or a placeholder naming the path if
/// the image can't be found. A text file, which Leanpub includes as code,
/// is drawn as a code block across the text, under the caption from the
/// attribute list above it (`{caption: "x", format: ini}`), if any.
final class ImageAttachmentCell: NSTextAttachmentCell {
    let picture: NSImage?
    /// The text of an included text file.
    let code: String?
    let path: String

    init(picture: NSImage?, code: String? = nil, path: String) {
        self.picture = picture
        self.code = code
        self.path = path
        super.init(imageCell: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static let placeholderAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]

    private var placeholderText: String { "Image not found: \(path)" }

    private func size(fittingWidth maxWidth: CGFloat) -> NSSize {
        guard let picture, picture.size.width > 0, picture.size.height > 0 else {
            let text = (placeholderText as NSString).size(withAttributes: Self.placeholderAttributes)
            return NSSize(width: min(ceil(text.width) + 20, maxWidth), height: 28)
        }
        let scale = min(1, maxWidth / picture.size.width)
        return NSSize(width: floor(picture.size.width * scale), height: floor(picture.size.height * scale))
    }

    // The text system lays out on the main thread.

    override func cellSize() -> NSSize {
        MainActor.assumeIsolated { size(fittingWidth: .greatestFiniteMagnitude) }
    }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        nonisolated(unsafe) let textContainer = textContainer
        return MainActor.assumeIsolated {
            // For now, images show at their actual size even when that is
            // wider than the text. Fitting them to `lineFrag` as the
            // placeholder is would shrink them to the text width.
            if let code, let textStorage = textContainer.layoutManager?.textStorage {
                // Less a point, so that the newline after it stays on the line.
                let width = max(floor(lineFrag.width - textContainer.lineFragmentPadding - position.x - 1), 100)
                caption = Self.caption(above: charIndex, in: textStorage)
                drawnWidth = 0
                return NSRect(origin: .zero, size: NSSize(width: width, height: codeLayout(code, width: width).height))
            }
            let maxWidth = picture == nil ? max(lineFrag.width - 2, 16) : .greatestFiniteMagnitude
            let size = size(fittingWidth: maxWidth)
            drawnWidth = size.width
            // A centred image's cell takes the rest of the line, and the
            // image is drawn in the middle of it.
            guard (textContainer.layoutManager as? EditorLayoutManager)?.centersImages == true,
                  let textStorage = textContainer.layoutManager?.textStorage,
                  Self.isAloneOnLine(at: charIndex, in: textStorage) else {
                return NSRect(origin: .zero, size: size)
            }
            // Less a point, so that the newline after it stays on the line.
            let rest = lineFrag.width - textContainer.lineFragmentPadding - position.x - 1
            return NSRect(origin: .zero, size: NSSize(width: max(size.width, floor(rest)), height: size.height))
        }
    }

    /// The width the image is drawn at, as last laid out.
    private var drawnWidth: CGFloat = 0

    /// Whether the image at `index` is the only thing shown on its line, so
    /// that it can be centred: everything else there is white space or
    /// hidden (comments and HTML tags), and it isn't in a table cell, whose
    /// alignment is its own. Leanpub's and HTML's alignments will count as
    /// formatting here too, once the editor reads them.
    static func isAloneOnLine(at index: Int, in text: NSAttributedString) -> Bool {
        guard index < text.length, text.blockStyle(at: index) != .table else { return false }
        let string = text.string as NSString
        let line = string.lineRange(for: NSRange(location: index, length: 0))
        for other in line.location..<NSMaxRange(line) where other != index {
            let character = string.character(at: other)
            if let scalar = Unicode.Scalar(character), CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            let attributes = text.attributes(at: other, effectiveRange: nil)
            if attributes[.markdownComment] != nil || attributes[.markdownHTML] != nil { continue }
            return false
        }
        return true
    }

    // An image sits on the baseline. The placeholder is centred on the
    // line's text instead.
    override func cellBaselineOffset() -> NSPoint {
        MainActor.assumeIsolated { NSPoint(x: 0, y: picture == nil ? -9 : 0) }
    }

    // MARK: - Included text

    /// The caption of the included file, from the attribute list on the
    /// hidden line above it, as last laid out.
    private var caption: String?

    static func caption(above index: Int, in text: NSAttributedString) -> String? {
        let string = text.string as NSString
        let line = string.lineRange(for: NSRange(location: index, length: 0))
        guard line.location > 0 else { return nil }
        let above = string.lineRange(for: NSRange(location: line.location - 1, length: 0))
        guard above.length > 0, let markdown = text.attribute(.markdownComment, at: above.location, effectiveRange: nil) as? String
        else { return nil }
        return AttributeList(line: markdown)?["caption"]
    }

    private static let codePadding: CGFloat = 8
    private static let captionAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.secondaryLabelColor,
    ]

    private static func codeText(_ code: String) -> NSAttributedString {
        NSAttributedString(string: code, attributes: [.font: BlockStyle.code.font(for: []), .foregroundColor: NSColor.textColor])
    }

    /// Where the caption and code go in a cell `width` wide, from its top,
    /// and the cell's height.
    private func codeLayout(_ code: String, width: CGFloat) -> (caption: NSRect?, box: NSRect, text: NSRect, height: CGFloat) {
        var y: CGFloat = 4
        var captionRect: NSRect?
        if let caption, !caption.isEmpty {
            let height = ceil((caption as NSString).size(withAttributes: Self.captionAttributes).height)
            captionRect = NSRect(x: 0, y: y, width: width, height: height)
            y += height + 4
        }
        let textWidth = width - 2 * Self.codePadding
        let textHeight = ceil(Self.codeText(code).boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                               options: [.usesLineFragmentOrigin]).height)
        let box = NSRect(x: 0, y: y, width: width, height: textHeight + 2 * Self.codePadding)
        let text = box.insetBy(dx: Self.codePadding, dy: Self.codePadding)
        return (captionRect, box, text, box.maxY + 4)
    }

    private func drawCode(_ code: String, in cellFrame: NSRect) {
        let layout = codeLayout(code, width: cellFrame.width)
        let offset = { (rect: NSRect) in rect.offsetBy(dx: cellFrame.minX, dy: cellFrame.minY) }
        if let caption, let rect = layout.caption {
            (caption as NSString).draw(with: offset(rect), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                       attributes: Self.captionAttributes)
        }
        InlineStyle.codeBackground.setFill()
        NSBezierPath(roundedRect: offset(layout.box), xRadius: 4, yRadius: 4).fill()
        Self.codeText(code).draw(with: offset(layout.text), options: [.usesLineFragmentOrigin])
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        if let code {
            drawCode(code, in: cellFrame)
            return
        }
        var cellFrame = cellFrame
        if drawnWidth > 0, drawnWidth < cellFrame.width {
            cellFrame = NSRect(x: cellFrame.minX + floor((cellFrame.width - drawnWidth) / 2), y: cellFrame.minY,
                               width: drawnWidth, height: cellFrame.height)
        }
        if let picture {
            picture.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        let box = NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSColor.quaternaryLabelColor.setFill()
        box.fill()
        NSColor.separatorColor.setStroke()
        box.stroke()
        let textRect = cellFrame.insetBy(dx: 10, dy: 0)
        let textHeight = (placeholderText as NSString).size(withAttributes: Self.placeholderAttributes).height
        (placeholderText as NSString).draw(
            with: NSRect(x: textRect.minX, y: textRect.midY - textHeight / 2, width: textRect.width, height: textHeight),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: Self.placeholderAttributes)
    }
}
