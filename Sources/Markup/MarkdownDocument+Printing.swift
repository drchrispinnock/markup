import AppKit

/// File > Print prints the document formatted, as the editor shows it,
/// whichever view the window is in.
extension MarkdownDocument {
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let printInfo = self.printInfo.copy() as! NSPrintInfo
        printInfo.dictionary().addEntries(from: printSettings)
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let pageWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let operation = NSPrintOperation(view: Self.printView(for: currentMarkdown, imageFolders: imageFolders,
                                                                   width: pageWidth), printInfo: printInfo)
        operation.jobTitle = displayName
        return operation
    }

    /// The folders the document's images are looked up in.
    var imageFolders: [URL] {
        (windowControllers.first as? EditorWindowController)?.imageFolders
            ?? [fileURL?.deletingLastPathComponent(), Settings.shared.imagesDirectory].compactMap { $0 }
    }

    /// A text view holding the formatted document, as tall as its text.
    /// It has no window, no spelling underlines and no caret.
    static func printView(for markdown: String, imageFolders: [URL], width: CGFloat) -> NSTextView {
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 0)
        textView.isEditable = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false
        // Dark text on paper, even in dark mode. Colours such as
        // `NSColor.textColor` take their value from the view's appearance.
        textView.appearance = NSAppearance(named: .aqua)

        textView.textStorage?.setAttributedString(EditorWindowController.formattedText(fromMarkdown: markdown,
                                                                                               imageFolders: imageFolders))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.sizeToFit()
        return textView
    }
}
