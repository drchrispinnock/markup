import AppKit
import MarkupCore
import Testing
@testable import Markup

/// Drives a real editor window through the same NSTextView commands that key
/// presses send. Each step runs in its own undo group, as an event would.
@MainActor
@Suite struct EditorTests {
    let document: MarkdownDocument
    let editor: EditorWindowController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.windowControllers.first as! EditorWindowController
    }

    private var textView: NSTextView { editor.textView }

    private func step(_ action: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        action()
        document.undoManager?.endUndoGrouping()
    }

    /// Types `text` one character at a time, as key presses would.
    private func type(_ text: String) {
        for character in text {
            step { textView.insertText(String(character), replacementRange: textView.selectedRange()) }
        }
    }

    private func press(_ command: Selector) {
        step { textView.doCommand(by: command) }
    }

    private func choose(_ style: BlockStyle) {
        step {
            editor.stylePopUp.selectItem(withTag: style.rawValue)
            editor.stylePopUp.sendAction(editor.stylePopUp.action, to: editor.stylePopUp.target)
        }
    }

    private func select(_ location: Int, _ length: Int = 0) {
        textView.setSelectedRange(NSRange(location: location, length: length))
    }

    private func fontSize(at location: Int) -> CGFloat {
        (textView.textStorage!.attribute(.font, at: location, effectiveRange: nil) as! NSFont).pointSize
    }

    private var selectedStyle: BlockStyle? {
        BlockStyle(rawValue: editor.stylePopUp.selectedTag())
    }

    @Test func loadingHidesMarkersAndSizesHeadings() {
        editor.load(markdown: "# Title\n## Section\nBody")
        #expect(textView.string == "Title\nSection\nBody")
        #expect(fontSize(at: 0) == BlockStyle.heading.font.pointSize)
        #expect(fontSize(at: 6) == BlockStyle.subheading.font.pointSize)
        #expect(fontSize(at: 14) == BlockStyle.paragraph.font.pointSize)
        #expect(editor.markdown == "# Title\n## Section\nBody")
    }

    @Test func typingAHeadingThenReturnGoesBackToParagraph() {
        choose(.heading)
        type("Title")
        press(#selector(NSResponder.insertNewline(_:)))
        #expect(selectedStyle == .paragraph)
        type("Body")
        #expect(editor.markdown == "# Title\nBody")
        #expect(fontSize(at: 6) == BlockStyle.paragraph.font.pointSize)
    }

    @Test func returnAtEndOfHeadingInsideDocumentStartsAParagraph() {
        editor.load(markdown: "# A\nB")
        select(1)
        press(#selector(NSResponder.insertNewline(_:)))
        type("x")
        #expect(editor.markdown == "# A\nx\nB")
    }

    @Test func returnInsideAHeadingSplitsItIntoTwoHeadings() {
        editor.load(markdown: "# Title")
        select(2)
        press(#selector(NSResponder.insertNewline(_:)))
        #expect(editor.markdown == "# Ti\n# tle")
    }

    @Test func choosingAStyleRestylesEverySelectedLine() {
        editor.load(markdown: "One\nTwo\nThree")
        select(1, 5)
        choose(.subheading)
        #expect(editor.markdown == "## One\n## Two\nThree")
    }

    @Test func popupFollowsTheCaret() {
        editor.load(markdown: "# Title\nBody")
        select(2)
        #expect(selectedStyle == .heading)
        select(8)
        #expect(selectedStyle == .paragraph)
    }

    @Test func typingAtTheStartOfAParagraphAfterAHeadingStaysParagraph() {
        editor.load(markdown: "# A\nB")
        select(2)
        type("x")
        #expect(editor.markdown == "# A\nxB")
    }

    @Test func joiningLinesTakesTheFirstLinesStyleAndUndoes() {
        editor.load(markdown: "# A\nB")
        select(2)
        press(#selector(NSResponder.deleteBackward(_:)))
        #expect(editor.markdown == "# AB")
        #expect(fontSize(at: 1) == BlockStyle.heading.font.pointSize)

        document.undoManager?.undo()
        #expect(editor.markdown == "# A\nB")
        #expect(fontSize(at: 2) == BlockStyle.paragraph.font.pointSize)

        document.undoManager?.redo()
        #expect(editor.markdown == "# AB")
    }

    @Test func styleChangeUndoesAndRedoes() {
        editor.load(markdown: "Title")
        choose(.heading)
        #expect(editor.markdown == "# Title")
        #expect(document.isDocumentEdited)
        document.undoManager?.undo()
        #expect(editor.markdown == "Title")
        document.undoManager?.redo()
        #expect(editor.markdown == "# Title")
    }

    @Test func savedDataIsTheMarkdown() throws {
        editor.load(markdown: "# Title\nBody\n")
        let data = try document.data(ofType: "net.daringfireball.markdown")
        #expect(String(decoding: data, as: UTF8.self) == "# Title\nBody\n")
    }
}

/// Lists: typed "- " and "[ ] " shortcuts, Return, Tab, checkboxes.
@MainActor
@Suite struct ListEditorTests {
    let document: MarkdownDocument
    let editor: EditorWindowController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.windowControllers.first as! EditorWindowController
    }

    private var textView: EditorTextView { editor.textView }

    private func step(_ action: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        action()
        document.undoManager?.endUndoGrouping()
    }

    private func type(_ text: String) {
        for character in text {
            step { textView.insertText(String(character), replacementRange: textView.selectedRange()) }
        }
    }

    private func press(_ command: Selector) {
        step { textView.doCommand(by: command) }
    }

    private func select(_ location: Int, _ length: Int = 0) {
        textView.setSelectedRange(NSRange(location: location, length: length))
    }

    private let enter = #selector(NSResponder.insertNewline(_:))
    private let tab = #selector(NSResponder.insertTab(_:))
    private let backtab = #selector(NSResponder.insertBacktab(_:))
    private let backspace = #selector(NSResponder.deleteBackward(_:))
    private let moveLeft = #selector(NSResponder.moveLeft(_:))

    @Test func dashSpaceStartsABulletAndReturnContinuesIt() {
        type("- Milk")
        #expect(textView.string == "\u{FFFC}Milk")
        press(enter)
        type("Eggs")
        #expect(editor.markdown == "- Milk\n- Eggs")
    }

    @Test func dashInsideALineIsJustText() {
        type("a - b")
        #expect(editor.markdown == "a - b")
    }

    @Test func returnOnAnEmptyItemEndsTheList() {
        type("- Milk")
        press(enter)
        press(enter)
        type("After")
        #expect(editor.markdown == "- Milk\nAfter")
    }

    @Test func tabNestsAndShiftTabUnnests() {
        type("- Eggs")
        press(enter)
        press(tab)
        type("Free range")
        #expect(editor.markdown == "- Eggs\n  - Free range")
        press(backtab)
        #expect(editor.markdown == "- Eggs\n- Free range")
    }

    @Test func nestingIsLimitedToOneLevelBelowTheItemAbove() {
        type("- a")
        press(tab)
        #expect(editor.markdown == "- a")
        press(enter)
        press(tab)
        press(tab)
        type("b")
        #expect(editor.markdown == "- a\n  - b")
    }

    @Test func returnOnAnEmptyNestedItemMovesItOut() {
        type("- a")
        press(enter)
        press(tab)
        press(enter)
        #expect(editor.markdown == "- a\n- ")
    }

    @Test func tabOutsideAListTypesATab() {
        type("a")
        press(tab)
        #expect(editor.markdown == "a\t")
    }

    @Test func nestedItemsAreIndented() {
        editor.load(markdown: "- a\n  - b")
        let style = textView.textStorage!.attribute(.paragraphStyle, at: 3, effectiveRange: nil) as! NSParagraphStyle
        #expect(style.firstLineHeadIndent == ListItem.indentPerLevel)
        #expect(style.headIndent == ListItem.indentPerLevel + ListItem.markerWidth)
    }

    @Test func checkboxShortcuts() {
        type("- [ ] Call")
        #expect(editor.markdown == "- [ ] Call")
        press(enter)
        type("Pay")
        #expect(editor.markdown == "- [ ] Call\n- [ ] Pay")
    }

    @Test func clickingACheckboxTicksItAndUndoes() {
        editor.load(markdown: "- [ ] Call\n- [ ] Pay")
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        let glyph = layoutManager.glyphIndexForCharacter(at: 6)
        var rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textView.textContainer!)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        let index = textView.markerIndex(at: NSPoint(x: rect.midX, y: rect.midY))
        #expect(index == 6)

        step { _ = textView.markerClickHandler?(6) }
        #expect(editor.markdown == "- [ ] Call\n- [x] Pay")
        #expect(document.isDocumentEdited)
        document.undoManager?.undo()
        #expect(editor.markdown == "- [ ] Call\n- [ ] Pay")
        document.undoManager?.redo()
        #expect(editor.markdown == "- [ ] Call\n- [x] Pay")
    }

    @Test func clickingTextIsNotAMarkerClick() {
        editor.load(markdown: "- [ ] Call")
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        #expect(textView.markerIndex(at: NSPoint(x: 200, y: 30)) == nil)
    }

    @Test func returnAfterACheckedItemStartsAnUncheckedOne() {
        editor.load(markdown: "- [x] Done")
        select(5)
        press(enter)
        type("Next")
        #expect(editor.markdown == "- [x] Done\n- [ ] Next")
    }

    @Test func backspaceAfterTheMarkerEndsTheItem() {
        editor.load(markdown: "- Milk")
        select(1)
        press(backspace)
        #expect(editor.markdown == "Milk")
        #expect(textView.textStorage!.attribute(.listLevel, at: 0, effectiveRange: nil) == nil)
    }

    @Test func caretCannotRestBeforeAMarker() {
        editor.load(markdown: "Top\n- Milk")
        select(4)
        #expect(textView.selectedRange().location == 5)
        press(moveLeft)
        #expect(textView.selectedRange().location == 3)
    }

    @Test func joiningAListLineOntoTheLineAboveDropsItsMarker() {
        editor.load(markdown: "- a\n- b")
        select(2)
        press(#selector(NSResponder.deleteForward(_:)))
        #expect(editor.markdown == "- ab")
    }

    @Test func pastedMarkdownListsBecomeLists() {
        step { textView.insertText("- a\n  - b\n- [x] c", replacementRange: textView.selectedRange()) }
        #expect(editor.markdown == "- a\n  - b\n- [x] c")
        #expect(!textView.string.contains("-"))
    }

    @Test func copyingWritesListsAsMarkdown() {
        editor.load(markdown: "Intro\n- a\n  - [ ] b")
        select(0, textView.string.utf16.count)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MarkupTests-\(UUID())"))
        pasteboard.clearContents()
        #expect(textView.writeSelection(to: pasteboard, type: .string))
        #expect(pasteboard.string(forType: .string) == "Intro\n- a\n  - [ ] b")
        pasteboard.releaseGlobally()
    }

    @Test func choosingAHeadingOnAListItemEndsTheList() {
        editor.load(markdown: "- Title\n- b")
        select(3)
        step {
            editor.stylePopUp.selectItem(withTag: BlockStyle.heading.rawValue)
            editor.stylePopUp.sendAction(editor.stylePopUp.action, to: editor.stylePopUp.target)
        }
        #expect(editor.markdown == "# Title\n- b")
    }

    @Test func undoingTheShortcutPutsTheTypingBack() {
        type("- ")
        document.undoManager?.undo()
        #expect(editor.markdown == "-")
        type("x")
        #expect(editor.markdown == "-x")
    }

    @Test func listsRoundTrip() {
        let markdown = "# Shopping\n- Milk\n  - Semi skimmed\n- [ ] Bread\n- [x] Eggs\n\nDone."
        editor.load(markdown: markdown)
        #expect(editor.markdown == markdown)
    }
}
