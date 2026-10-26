import AppKit
import MarkupCore

/// Front matter: the YAML header at the top of a Jekyll, Hugo or Pandoc file
/// (`MarkdownCodec.frontMatter(in:)`). The formatted view doesn't show it,
/// keeping it aside in `frontMatter` and writing it back first when saving,
/// so nothing formats or converts it. A badge in the header says it is there:
/// its tooltip shows it, and clicking it switches to the Markdown view, where
/// it is edited as text.
extension EditorViewController {
    /// How many Markdown lines the hidden front matter takes, before the
    /// formatted text's first line.
    var frontMatterLineCount: Int {
        guard !isShowingMarkdown, let frontMatter else { return 0 }
        let newlines = frontMatter.count { $0 == "\n" }
        return frontMatter.hasSuffix("\n") ? newlines : newlines + 1
    }

    /// Shows the badge in the formatted view of a file with front matter.
    func updateFrontMatterBadge() {
        let shows = !isShowingMarkdown && frontMatter != nil
        frontMatterBadge.isHidden = !shows
        frontMatterBadgeSpacing.isActive = shows
        frontMatterBadge.toolTip = frontMatter.map(Self.frontMatterToolTip)
    }

    /// The front matter's lines between its delimiters, up to a screenful,
    /// and how to edit it.
    static func frontMatterToolTip(_ frontMatter: String) -> String {
        let lines = frontMatter.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().dropLast(
            frontMatter.hasSuffix("\n") ? 2 : 1)
        let shown = lines.prefix(20).joined(separator: "\n") + (lines.count > 20 ? "\n…" : "")
        return (shown.isEmpty ? "" : shown + "\n\n") + "Click to edit it in the Markdown view."
    }

    /// The badge: switches to the Markdown view, at the front matter.
    @objc func showFrontMatter(_ sender: Any?) {
        setShowingMarkdown(true)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}

/// A button drawn as a badge: its title and image, small, on a rounded
/// tint like a variable's (`MarkupTag.color`).
final class BadgeButton: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        controlSize = .small
        font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = 5
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 12, height: size.height + 4)
    }

    /// The tint follows dark mode, so it is set again when that changes.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = MarkupTag.color.cgColor
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        viewDidChangeEffectiveAppearance()
    }
}
