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
        attachment.attachmentCell = ImageAttachmentCell(picture: fileURL(in: folders).flatMap(NSImage.init(contentsOf:)),
                                                        path: path)
        var attributes = attributes
        attributes[.attachment] = attachment
        attributes[.markdownImage] = markdown
        return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
    }

    /// The image's file: the path looked up in each folder in turn. Nil for
    /// web addresses and for files that can't be found.
    func fileURL(in folders: [URL]) -> URL? {
        guard !path.isEmpty, !path.contains("://") else { return nil }
        // Markdown paths are URLs, so spaces may be written as %20.
        let paths = [path, path.removingPercentEncoding].compactMap { $0 }
        let candidates = paths.contains { $0.hasPrefix("/") }
            ? paths.map { URL(fileURLWithPath: $0) }
            : folders.flatMap { folder in paths.map { folder.appendingPathComponent($0) } }
        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }
}

/// Draws an image at its actual size, or a placeholder naming the path if
/// the image can't be found.
final class ImageAttachmentCell: NSTextAttachmentCell {
    let picture: NSImage?
    let path: String

    init(picture: NSImage?, path: String) {
        self.picture = picture
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
        MainActor.assumeIsolated {
            // For now, images show at their actual size even when that is
            // wider than the text. Fitting them to `lineFrag` as the
            // placeholder is would shrink them to the text width.
            let maxWidth = picture == nil ? max(lineFrag.width - 2, 16) : .greatestFiniteMagnitude
            return NSRect(origin: .zero, size: size(fittingWidth: maxWidth))
        }
    }

    // An image sits on the baseline. The placeholder is centred on the
    // line's text instead.
    override func cellBaselineOffset() -> NSPoint {
        MainActor.assumeIsolated { NSPoint(x: 0, y: picture == nil ? -9 : 0) }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
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
