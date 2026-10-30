import AppKit

/// Leanpub's divisions of a book, each a line of its own: `{mainmatter}`
/// (the chapters) and `{backmatter}` (appendices and such). Markua no
/// longer has `{frontmatter}`, so that stays text. The formatted view
/// shows one as a rule across the text, labelled, carrying its Markdown as
/// a comment does (`.markdownComment`), so that saving and copying write it
/// back.
enum LeanpubDivision: String, CaseIterable {
    case mainmatter, backmatter

    /// The division `line` is, written exactly.
    init?(line: some StringProtocol) {
        guard line.hasPrefix("{"), line.hasSuffix("}"), let division = Self(rawValue: String(line.dropFirst().dropLast()))
        else { return nil }
        self = division
    }

    var markdown: String { "{\(rawValue)}" }

    var title: String {
        switch self {
        case .mainmatter: "Main Matter"
        case .backmatter: "Back Matter"
        }
    }

    /// The attachment character that shows the division, with the line's
    /// `attributes`.
    @MainActor
    func attachmentString(attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = DivisionAttachmentCell(label: title.uppercased())
        var attributes = attributes
        attributes[.attachment] = attachment
        attributes[.markdownComment] = markdown
        attributes[.toolTip] = "Leanpub: \(title.lowercased()) starts here"
        return NSAttributedString(string: "\u{FFFC}", attributes: attributes)
    }
}

/// Draws a rule across the rest of the line with a label in the middle.
final class DivisionAttachmentCell: NSTextAttachmentCell {
    let label: String

    init(label: String) {
        self.label = label
        super.init(imageCell: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    nonisolated private static let height: CGFloat = 24

    @MainActor private static var labelAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor, .kern: 1]
    }

    nonisolated override func cellSize() -> NSSize { NSSize(width: 200, height: Self.height) }

    nonisolated override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                                        glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        // Less a point, so that the newline after it stays on the line.
        let width = lineFrag.width - textContainer.lineFragmentPadding - position.x - 1
        return NSRect(x: 0, y: 0, width: max(floor(width), 100), height: Self.height)
    }

    // Centred on the line's text.
    nonisolated override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -7) }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let text = NSAttributedString(string: label, attributes: Self.labelAttributes)
        let size = text.size()
        let labelRect = NSRect(x: cellFrame.midX - ceil(size.width) / 2, y: cellFrame.midY - size.height / 2,
                               width: ceil(size.width), height: size.height)
        text.draw(in: labelRect)
        NSColor.separatorColor.setFill()
        let y = floor(cellFrame.midY)
        NSRect(x: cellFrame.minX, y: y, width: labelRect.minX - 8 - cellFrame.minX, height: 1).fill()
        NSRect(x: labelRect.maxX + 8, y: y, width: cellFrame.maxX - labelRect.maxX - 8, height: 1).fill()
    }
}
