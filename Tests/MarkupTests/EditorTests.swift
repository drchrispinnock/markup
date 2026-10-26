import AppKit
import MarkupCore
import Testing
@testable import Markup

/// Drives a real editor window through the same NSTextView commands that key
/// presses send. Each step runs in its own undo group, as an event would.
@MainActor
@Suite struct EditorTests {
    let document: MarkdownDocument
    let editor: EditorViewController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
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
        #expect(fontSize(at: 0) == BlockStyle.heading1.font.pointSize)
        #expect(fontSize(at: 6) == BlockStyle.heading2.font.pointSize)
        #expect(fontSize(at: 14) == BlockStyle.paragraph.font.pointSize)
        #expect(editor.markdown == "# Title\n## Section\nBody")
    }

    @Test func typingAHeadingThenReturnGoesBackToParagraph() {
        choose(.heading1)
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
        choose(.heading2)
        #expect(editor.markdown == "## One\n## Two\nThree")
    }

    @Test func popupFollowsTheCaret() {
        editor.load(markdown: "# Title\nBody")
        select(2)
        #expect(selectedStyle == .heading1)
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
        #expect(fontSize(at: 1) == BlockStyle.heading1.font.pointSize)

        document.undoManager?.undo()
        #expect(editor.markdown == "# A\nB")
        #expect(fontSize(at: 2) == BlockStyle.paragraph.font.pointSize)

        document.undoManager?.redo()
        #expect(editor.markdown == "# AB")
    }

    @Test func styleChangeUndoesAndRedoes() {
        editor.load(markdown: "Title")
        choose(.heading1)
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
    let editor: EditorViewController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
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
            editor.stylePopUp.selectItem(withTag: BlockStyle.heading1.rawValue)
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

    @Test func numberSpaceStartsANumberedListAndReturnContinuesIt() {
        type("1. Milk")
        #expect(textView.string == "\u{FFFC}Milk")
        press(enter)
        type("Eggs")
        press(enter)
        type("Bread")
        #expect(editor.markdown == "1. Milk\n2. Eggs\n3. Bread")
    }

    @Test func numberedListsNestAndEnd() {
        type("1. Eggs")
        press(enter)
        press(tab)
        type("Free range")
        press(enter)
        type("Organic")
        #expect(editor.markdown == "1. Eggs\n   1. Free range\n   2. Organic")
        press(enter)
        press(enter)
        type("Milk")
        #expect(editor.markdown == "1. Eggs\n   1. Free range\n   2. Organic\n2. Milk")
        press(enter)
        press(enter)
        type("After")
        #expect(editor.markdown == "1. Eggs\n   1. Free range\n   2. Organic\n2. Milk\nAfter")
    }

    @Test func aListStartsAtTheNumberTyped() {
        type("3. Three")
        press(enter)
        type("Four")
        #expect(editor.markdown == "3. Three\n4. Four")
    }

    @Test func savingNumbersItemsInOrder() {
        editor.load(markdown: "1. a\n1. b\n   - x\n   1. y\n   1. z\n1. c\n- bullet\n1. again")
        #expect(editor.markdown == "1. a\n2. b\n   - x\n   1. y\n   2. z\n3. c\n- bullet\n1. again")
        // Deleting an item renumbers those after it.
        let b = (textView.string as NSString).range(of: "b\n")
        step { textView.insertText("", replacementRange: NSRange(location: b.location - 1, length: b.length + 1)) }
        #expect(editor.markdown.hasPrefix("1. a\n   - x\n   1. y\n   2. z\n2. c\n"))
    }

    @Test func numbersShowByLevel() {
        #expect(ListItem.numberText(3, level: 0) == "3.")
        #expect(ListItem.numberText(4, level: 1) == "iv.")
        #expect(ListItem.numberText(1999, level: 1) == "mcmxcix.")
        #expect(ListItem.numberText(2, level: 2) == "b.")
        #expect(ListItem.numberText(28, level: 2) == "ab.")
        #expect(ListItem.numberText(1, level: 3) == "1.")
        editor.load(markdown: "1. a\n   1. b\n   2. c\n      1. d\n2. e")
        let storage = textView.textStorage!
        let starts = (textView.string as NSString).components(separatedBy: "\n").reduce(into: [0]) { $0.append($0.last! + ($1 as NSString).length + 1) }
        #expect(starts.dropLast().map { location in
            ListItem.numberText(storage.listNumber(atLineStart: location),
                                level: storage.attribute(.listLevel, at: location, effectiveRange: nil) as! Int)
        } == ["1.", "i.", "ii.", "a.", "2."])
    }

    @Test func numbersIndentTheirTextAndDontTick() {
        editor.load(markdown: "1. a")
        let style = textView.textStorage!.attribute(.paragraphStyle, at: 1, effectiveRange: nil) as! NSParagraphStyle
        #expect(style.headIndent == ListItem.numberWidth)
        step { #expect(textView.markerClickHandler?(0) == false) }
        #expect(editor.markdown == "1. a")
    }

    @Test func copyingWritesNumberedListsAsMarkdown() {
        editor.load(markdown: "Intro\n1. a\n1. b\n   1. c")
        select(0, textView.string.utf16.count)
        #expect(editor.plainText(for: textView.selectedRange()) == "Intro\n1. a\n2. b\n   1. c")
    }

    @Test func pastedNumberedListsBecomeLists() {
        step { textView.insertText("1. a\n2. b\n   1. c", replacementRange: textView.selectedRange()) }
        #expect(editor.markdown == "1. a\n2. b\n   1. c")
        #expect(!textView.string.contains("1."))
    }

    @Test func greaterThanSpaceStartsAQuote() {
        type("> Quoted")
        #expect(textView.string == "Quoted")
        #expect(textView.textStorage!.blockStyle(at: 0) == .quote)
        #expect(editor.stylePopUp.selectedTag() == BlockStyle.quote.rawValue)
        #expect(editor.markdown == "> Quoted")
    }

    @Test func greaterThanWithoutASpaceIsText() {
        type(">x and a > b")
        #expect(textView.textStorage!.blockStyle(at: 0) == .paragraph)
        // Markdown would read it as a quote, so it is escaped.
        #expect(editor.markdown == "\\>x and a > b")
    }

    @Test func returnContinuesAQuoteAndEndsItWhenEmpty() {
        type("> One")
        press(enter)
        type("Two")
        press(enter)
        press(enter)
        type("After")
        #expect(editor.markdown == "> One\n> Two\nAfter")
    }

    @Test func backspaceAtTheStartOfAQuoteLineEndsTheQuote() {
        editor.load(markdown: "Before\n> Quoted")
        select(7)
        press(backspace)
        #expect(editor.markdown == "Before\nQuoted")
        document.undoManager?.undo()
        #expect(editor.markdown == "Before\n> Quoted")
    }

    @Test func quoteCanBeChosenAndKeepsInlineStyles() {
        editor.load(markdown: "Some **bold** words")
        select(2)
        step {
            editor.stylePopUp.selectItem(withTag: BlockStyle.quote.rawValue)
            editor.stylePopUp.sendAction(editor.stylePopUp.action, to: editor.stylePopUp.target)
        }
        #expect(editor.markdown == "> Some **bold** words")
        let style = textView.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        #expect(style.headIndent == BlockStyle.quoteIndent)
    }

    @Test func emptyQuoteLinesStayInTheQuote() {
        let markdown = "> a\n>\n> b"
        editor.load(markdown: markdown)
        #expect(editor.markdown == markdown)
        select(0, textView.string.utf16.count)
        #expect(editor.plainText(for: textView.selectedRange()) == markdown)
    }

    @Test func pastedQuotesBecomeQuotes() {
        step { textView.insertText("> a\n>\n> b", replacementRange: textView.selectedRange()) }
        #expect(editor.markdown == "> a\n>\n> b")
        #expect(textView.string == "a\n\nb")
    }

    @Test func greaterThanInCodeStaysCode() {
        editor.load(markdown: "```\nx\n```")
        select(0)
        type("> ")
        #expect(editor.markdown == "```\n> x\n```")
    }

    @Test func listsRoundTrip() {
        let markdown = "# Shopping\n- Milk\n  - Semi skimmed\n- [ ] Bread\n- [x] Eggs\n\nDone."
        editor.load(markdown: markdown)
        #expect(editor.markdown == markdown)
    }
}

/// Typing "# ", "## " or "### " at the start of a line.
@MainActor
@Suite struct HeadingShortcutTests {
    let document: MarkdownDocument
    let editor: EditorViewController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
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

    private func fontSize(at location: Int) -> CGFloat {
        (textView.textStorage!.attribute(.font, at: location, effectiveRange: nil) as! NSFont).pointSize
    }

    private var selectedStyle: BlockStyle? {
        BlockStyle(rawValue: editor.stylePopUp.selectedTag())
    }

    @Test(arguments: [("# ", BlockStyle.heading1), ("## ", .heading2), ("### ", .heading3), ("#### ", .heading4),
                      ("##### ", .heading5), ("###### ", .heading6)])
    func markerAndSpaceMakeAHeading(marker: String, style: BlockStyle) {
        type(marker)
        #expect(textView.string == "")
        #expect(selectedStyle == style)
        type("Title")
        #expect(textView.string == "Title")
        #expect(fontSize(at: 0) == style.font.pointSize)
        #expect(editor.markdown == marker + "Title")
    }

    @Test func thePopupOffersHeadingsOneToThreeAndShowsFourToSix() {
        let titles = editor.stylePopUp.itemArray.filter { !$0.isHidden }.map(\.title)
        #expect(titles.prefix(4) == ["Heading 1", "Heading 2", "Heading 3", "Paragraph"])
        editor.load(markdown: "##### Five")
        #expect(selectedStyle == .heading5)
        #expect(editor.stylePopUp.titleOfSelectedItem == "Heading 5")
    }

    @Test func returnAfterATypedHeadingGoesBackToParagraph() {
        type("Intro")
        press(#selector(NSResponder.insertNewline(_:)))
        type("# Title")
        press(#selector(NSResponder.insertNewline(_:)))
        type("Body")
        #expect(editor.markdown == "Intro\n# Title\nBody")
    }

    @Test(arguments: ["#Title", "####### Seven", "a # b", " # Indented"])
    func otherHashesStayText(text: String) {
        type(text)
        #expect(textView.string == text)
    }

    @Test func typingTheMarkerBeforeExistingTextMakesItAHeading() {
        editor.load(markdown: "Title")
        type("## ")
        #expect(textView.string == "Title")
        #expect(editor.markdown == "## Title")
        #expect(textView.selectedRange().location == 0)
    }

    @Test func retypingTheMarkerOnAHeadingChangesItsLevel() {
        editor.load(markdown: "# Title")
        type("### ")
        #expect(editor.markdown == "### Title")
    }

    @Test func hashesInAListItemStayText() {
        type("- # x")
        #expect(editor.markdown == "- # x")
    }

    @Test func undoingTheShortcutPutsTheTypingBack() {
        type("# ")
        document.undoManager?.undo()
        #expect(editor.markdown == "\\#")
        type("x")
        #expect(textView.string == "#x")
    }

    @Test func pastedMarkdownHeadingsBecomeHeadings() {
        step { textView.insertText("# Title\n## Section\n- item", replacementRange: textView.selectedRange()) }
        #expect(textView.string == "Title\nSection\n\u{FFFC}item")
        #expect(editor.markdown == "# Title\n## Section\n- item")
    }

    @Test func rememberedStyleIsForgottenWhenTheCaretLeaves() {
        type("Intro")
        press(#selector(NSResponder.insertNewline(_:)))
        type("# ")
        #expect(selectedStyle == .heading1)
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(selectedStyle == .paragraph)
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        #expect(selectedStyle == .paragraph)
    }
}

/// The Formatted / Markdown switch in the header.
@MainActor
@Suite struct ViewModeTests {
    let document: MarkdownDocument
    let editor: EditorViewController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
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

    private func choose(segment: Int) {
        editor.viewModeControl.selectedSegment = segment
        editor.viewModeControl.sendAction(editor.viewModeControl.action, to: editor.viewModeControl.target)
    }

    private let sample = "# Title\n\\# not a heading\n- a\n  - [ ] b\n- [x] c"

    @Test func markdownViewShowsTheSavedText() throws {
        editor.load(markdown: sample)
        choose(segment: 1)
        #expect(textView.string == sample)
        #expect(!editor.stylePopUp.isEnabled)
        let font = textView.textStorage!.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        #expect(font.isFixedPitch)
        let data = try document.data(ofType: "net.daringfireball.markdown")
        #expect(String(decoding: data, as: UTF8.self) == sample)
    }

    @Test func switchingBackFormatsTheMarkdown() {
        editor.load(markdown: sample)
        choose(segment: 1)
        choose(segment: 0)
        #expect(textView.string == "Title\n# not a heading\n\u{FFFC}a\n\u{FFFC}b\n\u{FFFC}c")
        #expect(editor.stylePopUp.isEnabled)
        #expect(editor.markdown == sample)
    }

    @Test func markdownTypedInTheMarkdownViewIsFormattedOnSwitchingBack() {
        choose(segment: 1)
        type("## Section")
        #expect(textView.string == "## Section")
        press(#selector(NSResponder.insertNewline(_:)))
        type("- item")
        press(#selector(NSResponder.insertNewline(_:)))
        #expect(textView.string == "## Section\n- item\n")
        choose(segment: 0)
        #expect(textView.string == "Section\n\u{FFFC}item\n")
        #expect(editor.markdown == "## Section\n- item\n")
    }

    @Test func tabInTheMarkdownViewTypesATab() {
        choose(segment: 1)
        type("- a")
        press(#selector(NSResponder.insertTab(_:)))
        #expect(textView.string == "- a\t")
    }

    @Test func caretStaysOnTheSameText() {
        editor.load(markdown: "Intro\n## Section\n- item")
        textView.setSelectedRange(NSRange(location: 9, length: 0))  // "Sec|tion"
        choose(segment: 1)
        #expect(textView.selectedRange().location == 12)  // "## Sec|tion"
        textView.setSelectedRange(NSRange(location: 20, length: 0))  // "- i|tem"
        choose(segment: 0)
        #expect(textView.selectedRange().location == 16)  // marker, "i|tem"
    }

    @Test func switchingDoesNotMarkTheDocumentEdited() {
        editor.load(markdown: sample)
        choose(segment: 1)
        choose(segment: 0)
        #expect(!document.isDocumentEdited)
    }

    @Test func viewMenuItemTogglesAndShowsState() {
        let item = NSMenuItem(title: "Show Markdown", action: #selector(EditorViewController.toggleMarkdown(_:)), keyEquivalent: "")
        editor.toggleMarkdown(item)
        #expect(editor.isShowingMarkdown)
        #expect(editor.viewModeControl.selectedSegment == 1)
        _ = editor.validateMenuItem(item)
        #expect(item.state == .on)
        editor.toggleMarkdown(item)
        #expect(!editor.isShowingMarkdown)
    }

    @Test func appMenuHasAbout() {
        let appMenu = MainMenu.make().items.first!.submenu!
        let about = appMenu.items.first!
        #expect(about.title == "About Markup")
        #expect(about.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
    }
}

/// Spelling and grammar settings and the Edit > Spelling and Grammar menu.
@MainActor
@Suite struct SpellingAndGrammarTests {
    let defaults: UserDefaults
    let suiteName = "MarkupTests-\(UUID().uuidString)"

    init() {
        _ = NSApplication.shared
        defaults = UserDefaults(suiteName: suiteName)!
    }

    private func makeEditor() -> EditorTextView {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        let textView = document.editor.textView
        textView.checkingDefaults = defaults
        return textView
    }

    @Test func spellingAndGrammarAreOnAndAutocorrectIsOffByDefault() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let textView = makeEditor()
        #expect(textView.isContinuousSpellCheckingEnabled)
        #expect(textView.isGrammarCheckingEnabled)
        #expect(!textView.isAutomaticSpellingCorrectionEnabled)
    }

    @Test func togglingIsSavedAndReachesOtherEditors() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = makeEditor()
        let second = makeEditor()
        first.toggleGrammarChecking(nil)
        first.toggleAutomaticSpellingCorrection(nil)

        #expect(!defaults.bool(forKey: EditorTextView.checkGrammarKey))
        #expect(defaults.bool(forKey: EditorTextView.correctSpellingKey))
        #expect(!second.isGrammarCheckingEnabled)
        #expect(second.isAutomaticSpellingCorrectionEnabled)
        #expect(!makeEditor().isGrammarCheckingEnabled)
    }

    @Test func editorsWithOtherDefaultsAreNotAffected() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let otherName = "MarkupTests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: otherName) }
        let other = makeEditor()
        other.checkingDefaults = UserDefaults(suiteName: otherName)!
        makeEditor().toggleGrammarChecking(nil)
        #expect(other.isGrammarCheckingEnabled)
    }

    @Test func menuTogglesAreTickedToMatch() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let textView = makeEditor()
        let menu = MainMenu.make().items.first { $0.title == "Edit" }!.submenu!
            .items.first { $0.title == "Spelling and Grammar" }!.submenu!
        #expect(menu.items.map(\.title) == [
            "Show Spelling and Grammar", "Check Document Now", "",
            "Check Spelling While Typing", "Check Grammar With Spelling", "Correct Spelling Automatically",
        ])
        let grammar = menu.items[4]
        _ = textView.validateMenuItem(grammar)
        #expect(grammar.state == .on)
        textView.toggleGrammarChecking(grammar)
        _ = textView.validateMenuItem(grammar)
        #expect(grammar.state == .off)
    }
}

@MainActor
@Suite struct DevelopmentIconTests {
    /// The icon fills the standard rounded rect and nothing outside it.
    @Test func iconIsTheArtworkClippedToTheIconOutline() throws {
        let icon = try #require(DevelopmentIcon.make())
        let tiff = try #require(icon.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        #expect(bitmap.pixelsWide == 1024)
        func alpha(_ x: Int, _ y: Int) -> CGFloat { bitmap.colorAt(x: x, y: y)!.alphaComponent }
        #expect(alpha(512, 512) == 1)
        #expect(alpha(512, 102) == 1)
        #expect(alpha(50, 50) == 0)
        #expect(alpha(110, 110) == 0)
        #expect(alpha(512, 90) == 0)
    }
}

/// Long lines wrap at the window's width.
@MainActor
@Suite struct LineWrappingTests {
    let document: MarkdownDocument
    let editor: EditorViewController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.makeWindowControllers()
        editor = document.editor
    }

    private func expectTextFitsWindow() {
        let window = editor.view.window!
        window.layoutIfNeeded()
        let clipView = editor.textView.enclosingScrollView!.contentView
        #expect(editor.textView.frame.width == clipView.bounds.width)
        #expect(editor.textView.frame.width <= window.contentView!.bounds.width)
    }

    @Test func textViewIsAsWideAsTheWindow() {
        expectTextFitsWindow()
    }

    @Test func textViewFollowsTheWindowWhenResized() {
        let window = editor.view.window!
        window.setContentSize(NSSize(width: 520, height: 400))
        expectTextFitsWindow()
        window.setContentSize(NSSize(width: 1100, height: 700))
        expectTextFitsWindow()
    }

    @Test func headerControlsNeverOverlap() {
        let window = editor.view.window!
        window.setContentSize(NSSize(width: 400, height: 400))
        window.layoutIfNeeded()
        #expect(editor.superscriptButton.frame.maxX < editor.linkButton.frame.minX)
        #expect(window.contentView!.bounds.width >= editor.viewModeControl.frame.maxX)
    }

    /// Including a heading, a list item and a word too long for one line.
    @Test func longLinesWrap() {
        editor.load(markdown: "# " + String(repeating: "heading ", count: 40) + "\n"
            + "- " + String(repeating: "item ", count: 80) + "\n"
            + String(repeating: "x", count: 400))
        editor.view.window!.setContentSize(NSSize(width: 520, height: 400))
        editor.view.window!.layoutIfNeeded()
        let textView = editor.textView
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        let used = layoutManager.usedRect(for: textView.textContainer!)
        #expect(used.height > 100)
        #expect(used.maxX + textView.textContainerOrigin.x <= textView.enclosingScrollView!.contentView.bounds.width)
    }
}

/// File > Print prints the formatted document.
@MainActor
@Suite struct PrintingTests {
    let document: MarkdownDocument
    let editor: EditorViewController
    static let sample = "# Title\n\nSome text.\n\n- one\n  - [x] done\n"

    init() throws {
        _ = NSApplication.shared
        document = MarkdownDocument()
        try document.read(from: Data(Self.sample.utf8), ofType: "net.daringfireball.markdown")
        document.makeWindowControllers()
        editor = document.editor
    }

    private func printedText() throws -> NSTextStorage {
        let operation = try document.printOperation(withSettings: [:])
        return try #require((operation.view as? NSTextView)?.textStorage)
    }

    @Test func printsTheFormattedText() throws {
        let text = try printedText()
        #expect(text.string == "Title\n\nSome text.\n\n\u{FFFC}one\n\u{FFFC}done\n")
        #expect(text.blockStyle(at: 0) == .heading1)
        #expect(text.attribute(.listMarker, at: 19, effectiveRange: nil) as? Int == ListMarker.bullet.rawValue)
    }

    @Test func printsFormattedTextFromTheMarkdownView() throws {
        editor.setShowingMarkdown(true)
        #expect(try printedText().string == "Title\n\nSome text.\n\n\u{FFFC}one\n\u{FFFC}done\n")
    }

    @Test func printsUnsavedEdits() throws {
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.textView.insertText("!", replacementRange: editor.textView.selectedRange())
        #expect(try printedText().string.hasPrefix("Title!\n"))
    }

    @Test func pageIsTheWidthBetweenTheMargins() throws {
        let operation = try document.printOperation(withSettings: [:])
        let info = operation.printInfo
        let view = try #require(operation.view)
        #expect(view.frame.width == info.paperSize.width - info.leftMargin - info.rightMargin)
        #expect(view.frame.height > 0)
        #expect(view.appearance?.name == .aqua)
    }

    @Test func printsToPDF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupPrint-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let long = Self.sample + String(repeating: "A long paragraph that wraps across the page. ", count: 400)
        editor.load(markdown: long)
        let operation = try document.printOperation(withSettings: [
            .jobDisposition: NSPrintInfo.JobDisposition.save,
            .jobSavingURL: url,
        ])
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        #expect(operation.run())
        let pdf = try #require(CGPDFDocument(url as CFURL))
        #expect(pdf.numberOfPages >= 2)
    }
}

/// Markup > Settings.
@MainActor
@Suite struct SettingsTests {
    let suiteName = "MarkupTests-\(UUID().uuidString)"
    let settings: Settings

    init() {
        _ = NSApplication.shared
        settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    @Test func imagesDirectoryIsUnsetByDefault() {
        defer { settings.defaults.removePersistentDomain(forName: suiteName) }
        #expect(settings.imagesDirectory == nil)
    }

    @Test func imagesDirectoryIsSaved() {
        defer { settings.defaults.removePersistentDomain(forName: suiteName) }
        settings.imagesDirectory = URL(fileURLWithPath: "/Users/someone/Pictures/Blog", isDirectory: true)
        let reread = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        #expect(reread.imagesDirectory?.path == "/Users/someone/Pictures/Blog")
        reread.imagesDirectory = nil
        #expect(settings.imagesDirectory == nil)
    }

    @Test func windowShowsAndClearsTheImagesDirectory() {
        defer { settings.defaults.removePersistentDomain(forName: suiteName) }
        let controller = SettingsWindowController(settings: settings)
        #expect(controller.imagesDirectoryControl.url == nil)
        #expect(!controller.clearButton.isEnabled)

        let folder = URL(fileURLWithPath: "/tmp", isDirectory: true)
        controller.setImagesDirectory(folder)
        #expect(settings.imagesDirectory == folder)
        #expect(controller.imagesDirectoryControl.url == folder)
        #expect(controller.clearButton.isEnabled)

        controller.clearButton.performClick(nil)
        #expect(settings.imagesDirectory == nil)
        #expect(controller.imagesDirectoryControl.url == nil)
        #expect(!controller.clearButton.isEnabled)

    }

    @Test func appMenuHasSettings() {
        let item = MainMenu.make().items[0].submenu!.items.first { $0.title == "Settings…" }
        #expect(item?.action == #selector(AppDelegate.showSettings(_:)))
        #expect(item?.keyEquivalent == ",")
    }
}

/// Images: shown in the formatted view, saved as their Markdown, inserted
/// from the images directory.
@MainActor
@Suite struct ImageTests {
    let document: MarkdownDocument
    let editor: EditorViewController
    let suiteName = "MarkupTests-\(UUID().uuidString)"
    let imagesDirectory: URL

    init() throws {
        _ = NSApplication.shared
        imagesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupImages-\(UUID())")
        try FileManager.default.createDirectory(at: imagesDirectory.appendingPathComponent("cats"),
                                                withIntermediateDirectories: true)
        try Self.writePNG(width: 2000, height: 1000, to: imagesDirectory.appendingPathComponent("cats/tom.png"))

        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
        editor.settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        editor.settings.imagesDirectory = imagesDirectory
    }

    private func cleanUp() {
        editor.settings.defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: imagesDirectory)
    }

    static func writePNG(width: Int, height: Int, to url: URL) throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.systemBlue.setFill()
        NSBezierPath(ovalIn: NSRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2)).fill()
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    private var textView: EditorTextView { editor.textView }
    private var storage: NSTextStorage { editor.storage }

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

    private func cell(at index: Int) -> ImageAttachmentCell? {
        (storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment)?.attachmentCell
            as? ImageAttachmentCell
    }

    @Test func showsImagesAndSavesThemUnchanged() {
        defer { cleanUp() }
        let markdown = "# A ![cat](cats/tom.png) title\n\n- ![](<cats/tom.png> \"Tom\") item\nMissing ![x](nope.png)."
        editor.load(markdown: markdown)
        #expect(storage.string == "A \u{FFFC} title\n\n\u{FFFC}\u{FFFC} item\nMissing \u{FFFC}.")
        #expect(cell(at: 2)?.picture != nil)
        #expect(storage.blockStyle(at: 2) == .heading1)
        #expect(cell(at: 12)?.picture != nil)
        #expect(cell(at: 27)?.picture == nil)
        #expect(cell(at: 27)?.path == "nope.png")
        #expect(editor.markdown == markdown)
    }

    @Test func looksInTheImagesDirectoryThenTheDocumentsFolderThenResourcesThenImagesThenAbove() throws {
        defer { cleanUp() }
        let documentFolder = imagesDirectory.appendingPathComponent("site/doc")
        document.fileURL = documentFolder.appendingPathComponent("post.md")
        let folders = [imagesDirectory, documentFolder, documentFolder.appendingPathComponent("resources"),
                       documentFolder.appendingPathComponent("images"), imagesDirectory.appendingPathComponent("site")]
        #expect(editor.imageFolders.map(\.path) == folders.map(\.path))
        for folder in folders.dropFirst() {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("cats"), withIntermediateDirectories: true)
            try Self.writePNG(width: 10, height: 10, to: folder.appendingPathComponent("cats/tom.png"))
        }
        // Each folder in turn is used once the ones before it lack the file.
        for folder in folders {
            #expect(MarkdownImage(alt: "", path: "cats/tom.png").fileURL(in: editor.imageFolders)?.path
                == folder.appendingPathComponent("cats/tom.png").path)
            try FileManager.default.removeItem(at: folder.appendingPathComponent("cats/tom.png"))
        }
        #expect(MarkdownImage(alt: "", path: "cats/tom.png").fileURL(in: editor.imageFolders) == nil)
        try Self.writePNG(width: 10, height: 10, to: imagesDirectory.appendingPathComponent("cats/tom.png"))
        #expect(MarkdownImage(alt: "", path: "cats%2Ftom.png").fileURL(in: editor.imageFolders) != nil)
        #expect(MarkdownImage(alt: "", path: "https://example.com/a.png").fileURL(in: editor.imageFolders) == nil)
        #expect(MarkdownImage(alt: "", path: "//example.com/cats/tom.png").fileURL(in: editor.imageFolders) == nil)
    }

    @Test func aLeadingSlashIsDroppedToLookThePathUp() throws {
        defer { cleanUp() }
        let found = MarkdownImage(alt: "", path: "/cats/tom.png").fileURL(in: editor.imageFolders)
        #expect(found?.path == imagesDirectory.appendingPathComponent("cats/tom.png").path)
        // A full path in none of the folders, as Insert Image writes, is
        // still found.
        let full = imagesDirectory.appendingPathComponent("cats/tom.png").path
        #expect(MarkdownImage(alt: "", path: full).fileURL(in: [])?.path == full)
        // The text keeps its slash.
        editor.load(markdown: "![](/cats/tom.png)")
        #expect(cell(at: 0)?.picture != nil)
        #expect(editor.markdown == "![](/cats/tom.png)")
    }

    @Test func imagesShowAtTheirActualSize() throws {
        defer { cleanUp() }
        editor.load(markdown: "![](cats/tom.png) ![](missing.png)")
        let line = NSRect(x: 0, y: 0, width: 502, height: 20)
        let image = try #require(cell(at: 0))
        #expect(image.cellSize() == NSSize(width: 2000, height: 1000))
        #expect(image.cellFrame(for: textView.textContainer!, proposedLineFragment: line,
                                glyphPosition: .zero, characterIndex: 0).size == NSSize(width: 2000, height: 1000))
        // The placeholder still fits the text.
        let placeholder = try #require(cell(at: 2))
        #expect(placeholder.cellFrame(for: textView.textContainer!, proposedLineFragment: line,
                                      glyphPosition: .zero, characterIndex: 2).width <= 500)
    }

    @Test func typedImageMarkdownBecomesTheImage() {
        defer { cleanUp() }
        type("See ![a cat](cats/tom.png")
        #expect(cell(at: 4) == nil)
        type(") here")
        #expect(storage.string == "See \u{FFFC} here")
        #expect(cell(at: 4)?.picture != nil)
        #expect(textView.selectedRange().location == 10)
        #expect(editor.markdown == "See ![a cat](cats/tom.png) here")
    }

    /// As with the other shortcuts, undo takes back the conversion and the
    /// keystroke that triggered it.
    @Test func undoTurnsTheImageBackIntoText() {
        defer { cleanUp() }
        type("![](cats/tom.png)")
        #expect(storage.string == "\u{FFFC}")
        document.undoManager?.undo()
        #expect(storage.string == "![](cats/tom.png")
        type("x")
        #expect(storage.string == "![](cats/tom.pngx")
    }

    @Test func copiesImagesAsMarkdownAndPastingConvertsThem() {
        defer { cleanUp() }
        editor.load(markdown: "- a ![x](cats/tom.png)")
        let all = NSRange(location: 0, length: storage.length)
        #expect(editor.plainText(for: all) == "- a ![x](cats/tom.png)")
        step { textView.setSelectedRange(NSRange(location: storage.length, length: 0)) }
        step { textView.insertText("\n- b ![y](cats/tom.png)", replacementRange: textView.selectedRange()) }
        #expect(storage.string == "\u{FFFC}a \u{FFFC}\n\u{FFFC}b \u{FFFC}")
        #expect(editor.markdown == "- a ![x](cats/tom.png)\n- b ![y](cats/tom.png)")
    }

    @Test func insertsAnImageRelativeToTheImagesDirectory() {
        defer { cleanUp() }
        type("Hello ")
        step { editor.insertImage(path: "cats/tom.png", alt: "Tom [the cat]") }
        #expect(storage.string == "Hello \u{FFFC}")
        #expect(cell(at: 6)?.picture != nil)
        #expect(textView.selectedRange().location == 7)
        #expect(editor.markdown == #"Hello ![Tom \[the cat\]](cats/tom.png)"#)
    }

    @Test func insertedPathsAreTheShortestThatFindTheImage() throws {
        defer { cleanUp() }
        let documentFolder = imagesDirectory.appendingPathComponent("doc")
        document.fileURL = documentFolder.appendingPathComponent("post.md")
        let manager = FileManager.default
        for folder in ["doc/resources/icons", "doc/images", "doc/drafts"] {
            try manager.createDirectory(at: imagesDirectory.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for name in ["doc/here.png", "doc/drafts/sketch.png", "doc/resources/logo.png", "doc/resources/icons/star.png",
                     "doc/images/photo.png", "doc/images/tom.png"] {
            try Self.writePNG(width: 4, height: 4, to: imagesDirectory.appendingPathComponent(name))
        }
        func path(_ name: String) -> String { editor.imagePath(for: imagesDirectory.appendingPathComponent(name)) }
        #expect(path("cats/tom.png") == "cats/tom.png")
        #expect(path("doc/here.png") == "here.png")
        #expect(path("doc/drafts/sketch.png") == "drafts/sketch.png")
        #expect(path("doc/resources/logo.png") == "logo.png")
        #expect(path("doc/resources/icons/star.png") == "icons/star.png")
        #expect(path("doc/images/photo.png") == "photo.png")
        // Anything shorter would find a different file.
        try manager.createDirectory(at: imagesDirectory.appendingPathComponent("doc/images/cats"), withIntermediateDirectories: true)
        try Self.writePNG(width: 4, height: 4, to: imagesDirectory.appendingPathComponent("doc/images/cats/tom.png"))
        try Self.writePNG(width: 4, height: 4, to: imagesDirectory.appendingPathComponent("photo.png"))
        #expect(path("doc/images/cats/tom.png") == "images/cats/tom.png")
        #expect(path("doc/images/photo.png") == "images/photo.png")

        let elsewhere = manager.temporaryDirectory.appendingPathComponent("MarkupElsewhere-\(UUID()).png")
        try Self.writePNG(width: 4, height: 4, to: elsewhere)
        defer { try? manager.removeItem(at: elsewhere) }
        #expect(editor.imagePath(for: elsewhere) == elsewhere.resolvingSymlinksInPath().path)
    }

    @Test func pathsAreRelativeToTheImagesDirectoryOnly() {
        defer { cleanUp() }
        let file = imagesDirectory.appendingPathComponent("cats/tom.png")
        #expect(EditorViewController.path(of: file, relativeTo: imagesDirectory) == "cats/tom.png")
        #expect(EditorViewController.path(of: imagesDirectory, relativeTo: imagesDirectory) == nil)
        #expect(EditorViewController.path(of: URL(fileURLWithPath: "/etc/hosts"), relativeTo: imagesDirectory) == nil)
        let sibling = URL(fileURLWithPath: imagesDirectory.path + "-other/a.png")
        #expect(EditorViewController.path(of: sibling, relativeTo: imagesDirectory) == nil)
    }

    @Test func buttonIsOffInTheMarkdownView() {
        defer { cleanUp() }
        #expect(editor.imageButton.isEnabled)
        editor.setShowingMarkdown(true)
        #expect(!editor.imageButton.isEnabled)
        editor.setShowingMarkdown(false)
        #expect(editor.imageButton.isEnabled)
    }

    @Test func printsImages() throws {
        defer { cleanUp() }
        editor.load(markdown: "Before\n![](cats/tom.png)\nAfter")
        let operation = try document.printOperation(withSettings: [:])
        let text = try #require((operation.view as? NSTextView)?.textStorage)
        let attachment = text.attribute(.attachment, at: 7, effectiveRange: nil) as? NSTextAttachment
        #expect((attachment?.attachmentCell as? ImageAttachmentCell)?.picture != nil)

    }
}

/// Bold and italic text: the B and I buttons, Format menu and typed asterisks.
@MainActor
@Suite struct EmphasisTests {
    let document: MarkdownDocument
    let editor: EditorViewController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
    }

    private var textView: EditorTextView { editor.textView }
    private var storage: NSTextStorage { editor.storage }

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

    private func select(_ location: Int, _ length: Int = 0) {
        step { textView.setSelectedRange(NSRange(location: location, length: length)) }
    }

    private func traits(at index: Int) -> NSFontDescriptor.SymbolicTraits {
        (storage.attribute(.font, at: index, effectiveRange: nil) as! NSFont).fontDescriptor.symbolicTraits
    }

    @Test func showsAndSavesBoldAndItalic() {
        let markdown = "a **b** *c* ***d***\n# T **e**\n- *f*"
        editor.load(markdown: markdown)
        #expect(storage.string == "a b c d\nT e\n\u{FFFC}f")
        #expect(storage.isBold(at: 2) && !storage.isItalic(at: 2) && traits(at: 2).contains(.bold))
        #expect(storage.isItalic(at: 4) && !storage.isBold(at: 4) && traits(at: 4).contains(.italic))
        #expect(storage.isBold(at: 6) && storage.isItalic(at: 6) && traits(at: 6).isSuperset(of: [.bold, .italic]))
        #expect(!storage.isBold(at: 3) && !traits(at: 3).contains(.bold))
        #expect(storage.isBold(at: 10) && storage.blockStyle(at: 10) == .heading1)
        #expect(storage.isItalic(at: 13) && traits(at: 13).contains(.italic))
        #expect(editor.markdown == markdown)
    }

    @Test func boldButtonTogglesTheSelection() {
        type("one two")
        select(4, 3)
        step { editor.boldButton.performClick(nil) }
        #expect(editor.markdown == "one **two**")
        #expect(editor.boldButton.state == .on)
        step { editor.boldButton.performClick(nil) }
        #expect(editor.markdown == "one two")
        #expect(editor.boldButton.state == .off)
    }

    @Test func mixedSelectionBecomesAllBoldThenPlain() {
        editor.load(markdown: "**one** two")
        select(0, 7)
        #expect(editor.boldButton.state == .off)
        step { editor.toggleBold(nil) }
        #expect(editor.markdown == "**one two**")
        step { editor.toggleBold(nil) }
        #expect(editor.markdown == "one two")
    }

    @Test func boldAndItalicCombine() {
        type("word")
        select(0, 4)
        step { editor.toggleBold(nil) }
        step { editor.toggleItalic(nil) }
        #expect(editor.markdown == "***word***")
        #expect(editor.italicButton.state == .on && editor.boldButton.state == .on)
    }

    @Test func undoPutsTheStyleBack() {
        type("word")
        select(0, 4)
        step { editor.toggleItalic(nil) }
        document.undoManager?.undo()
        #expect(editor.markdown == "word")
        document.undoManager?.redo()
        #expect(editor.markdown == "*word*")
    }

    @Test func buttonWithNoSelectionChangesWhatIsTypedNext() {
        type("a ")
        step { editor.toggleBold(nil) }
        #expect(editor.boldButton.state == .on)
        type("bold")
        step { editor.toggleBold(nil) }
        type(" c")
        #expect(editor.markdown == "a **bold** c")
    }

    @Test func typingContinuesTheStyleBeforeTheCaret() {
        editor.load(markdown: "**ab** c")
        select(2)
        type("x")
        select(4)
        type("y")
        #expect(editor.markdown == "**abx** yc")
    }

    @Test func typedAsterisksBecomeEmphasis() {
        type("an *it* and **bo** and ***bi*** x")
        #expect(storage.string == "an it and bo and bi x")
        #expect(editor.markdown == "an *it* and **bo** and ***bi*** x")
        #expect(textView.selectedRange().location == storage.length)
    }

    /// The closing asterisk waits for the next character, so typing "**"
    /// closes bold rather than italic.
    @Test func closingAsteriskWaitsForTheNextCharacter() {
        type("**b*")
        #expect(storage.string == "**b*")
        type("*")
        #expect(storage.string == "**b**")
        type(".")
        #expect(storage.string == "b.")
        #expect(storage.isBold(at: 0))
    }

    @Test func pastedEmphasisIsConverted() {
        step { textView.insertText("x **y** *z*", replacementRange: textView.selectedRange()) }
        #expect(storage.string == "x y z")
        #expect(editor.markdown == "x **y** *z*")
    }

    @Test func literalAsterisksStayText() {
        type("2 * 3 * 4 and a*")
        #expect(storage.string == "2 * 3 * 4 and a*")
        #expect(editor.markdown == "2 * 3 * 4 and a*")
    }

    @Test func styleChangesKeepEmphasis() {
        editor.load(markdown: "a **b** *c*")
        select(0)
        editor.stylePopUp.selectItem(withTag: BlockStyle.heading1.rawValue)
        step { editor.styleChosen(editor.stylePopUp) }
        #expect(editor.markdown == "# a **b** *c*")
        #expect(traits(at: 2).contains(.bold) && traits(at: 4).contains(.italic))
        #expect((storage.attribute(.font, at: 4, effectiveRange: nil) as! NSFont).pointSize == BlockStyle.heading1.font.pointSize)
    }

    @Test func joiningLinesKeepsEmphasis() {
        editor.load(markdown: "# Head\n*it*")
        select(4)
        step { textView.deleteForward(nil) }
        #expect(editor.markdown == "# Head*it*")
        #expect(traits(at: 4).contains(.italic))
        #expect((storage.attribute(.font, at: 4, effectiveRange: nil) as! NSFont).pointSize == BlockStyle.heading1.font.pointSize)
    }

    @Test func copiesEmphasisAsMarkdown() {
        editor.load(markdown: "a **b**\n- *c*")
        #expect(editor.plainText(for: NSRange(location: 2, length: storage.length - 2)) == "**b**\n- *c*")
    }

    @Test func buttonsAndMenuAreOffInTheMarkdownView() {
        let format = MainMenu.make().items.first { $0.title == "Format" }!.submenu!
        let bold = format.items[0], italic = format.items[1], strike = format.items[2]
        #expect(bold.keyEquivalent == "b" && italic.keyEquivalent == "i" && strike.keyEquivalent == "X")
        #expect(editor.validateMenuItem(bold) && editor.validateMenuItem(strike))
        editor.setShowingMarkdown(true)
        #expect(!editor.boldButton.isEnabled && !editor.italicButton.isEnabled && !editor.strikethroughButton.isEnabled)
        #expect(!editor.validateMenuItem(bold) && !editor.validateMenuItem(italic) && !editor.validateMenuItem(strike))
    }

    @Test func showsAndSavesStrikethrough() {
        let markdown = "a ~~b~~ c ~~**d**~~"
        editor.load(markdown: markdown)
        #expect(storage.string == "a b c d")
        #expect(storage.inlineStyles(at: 2) == [.strikethrough])
        #expect(storage.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(storage.attribute(.strikethroughStyle, at: 3, effectiveRange: nil) == nil)
        #expect(storage.inlineStyles(at: 6) == [.bold, .strikethrough])
        #expect(editor.markdown == markdown)
    }

    @Test func strikethroughButtonTogglesTheSelection() {
        type("one two")
        select(0, 3)
        step { editor.strikethroughButton.performClick(nil) }
        #expect(editor.markdown == "~~one~~ two")
        #expect(editor.strikethroughButton.state == .on)
        step { editor.toggleStrikethrough(nil) }
        #expect(editor.markdown == "one two")
        #expect(storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil)
    }

    @Test func typedTildesBecomeStrikethrough() {
        type("a ~~gone~~ b and x ~ y")
        #expect(storage.string == "a gone b and x ~ y")
        #expect(editor.markdown == "a ~~gone~~ b and x ~ y")
    }

    @Test func subscriptAndSuperscriptButtonsToggleTheSelection() {
        type("H2O x2")
        select(1, 1)
        step { editor.subscriptButton.performClick(nil) }
        #expect(editor.markdown == "H~2~O x2")
        #expect(editor.subscriptButton.state == .on && editor.superscriptButton.state == .off)
        let offset = storage.attribute(.baselineOffset, at: 1, effectiveRange: nil) as? CGFloat
        #expect(offset.map { $0 < 0 } == true)
        let small = storage.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        let normal = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(small!.pointSize < normal!.pointSize)

        select(5, 1)
        step { editor.toggleSuperscript(nil) }
        #expect(editor.markdown == "H~2~O x^2^")
        #expect((storage.attribute(.baselineOffset, at: 5, effectiveRange: nil) as? CGFloat).map { $0 > 0 } == true)
        // Subscript replaces superscript.
        step { editor.toggleSubscript(nil) }
        #expect(editor.markdown == "H~2~O x~2~")
        step { editor.toggleSubscript(nil) }
        #expect(editor.markdown == "H~2~O x2")
        #expect(storage.attribute(.baselineOffset, at: 5, effectiveRange: nil) == nil)
    }

    @Test func superscriptButtonWithNoSelectionStylesWhatIsTyped() {
        type("x")
        step { editor.superscriptButton.performClick(nil) }
        type("2")
        step { editor.superscriptButton.performClick(nil) }
        type(" y")
        #expect(editor.markdown == "x^2^ y")
    }

    @Test func typedTildesAndCaretsBecomeSubscriptAndSuperscript() {
        type("H~2~O and x^2^ but x^2 + y^2 and my_var name")
        #expect(storage.string == "H2O and x2 but x^2 + y^2 and my_var name")
        #expect(storage.inlineStyles(at: 1) == [.subscript])
        #expect(storage.inlineStyles(at: 9) == [.superscript])
        #expect(editor.markdown == "H~2~O and x^2^ but x^2 + y^2 and my_var name")
    }

    @Test func linksTheSelection() {
        type("one two three")
        select(4, 3)
        step { editor.setLink("https://example.com", in: editor.linkTargetRange()) }
        #expect(editor.markdown == "one [two](https://example.com) three")
        #expect(storage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor == InlineStyle.linkColor)
        #expect(storage.attribute(.underlineStyle, at: 4, effectiveRange: nil) != nil)
        #expect(storage.attribute(.toolTip, at: 4, effectiveRange: nil) as? String == "https://example.com")
        #expect(storage.attribute(.underlineStyle, at: 3, effectiveRange: nil) == nil)
        textView.undoManager?.undo()
        #expect(editor.markdown == "one two three")
    }

    @Test func typingContinuesALinkOnlyInsideIt() {
        type("a b c")
        select(2, 1)
        step { editor.setLink("notes.md", in: editor.linkTargetRange()) }
        select(3)
        type("x")
        #expect(editor.markdown == "a [b](notes.md)x c")
        select(2)
        type("y")
        #expect(editor.markdown == "a y[b](notes.md)x c")
        // Typing inside a link extends it.
        select(3, 2)
        step { editor.setLink("notes.md", in: editor.linkTargetRange()) }
        select(4)
        type("z")
        #expect(editor.markdown == "a y[bzx](notes.md) c")
    }

    @Test func caretInALinkEditsOrRemovesTheWholeLink() {
        editor.load(markdown: "see [the docs](a.md) now")
        select(8)
        #expect(editor.linkTargetRange() == NSRange(location: 4, length: 8))
        step { editor.setLink("b.md", in: editor.linkTargetRange()) }
        #expect(editor.markdown == "see [the docs](b.md) now")
        step { editor.setLink(nil, in: editor.linkTargetRange()) }
        #expect(editor.markdown == "see the docs now")
        #expect(storage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor == .textColor)
        #expect(storage.attribute(.underlineStyle, at: 5, effectiveRange: nil) == nil)
    }

    @Test func linkWithNoSelectionInsertsTheLinkAsItsText() {
        type("go ")
        step { editor.setLink("https://x.org", in: editor.linkTargetRange()) }
        #expect(editor.markdown == "go [https://x.org](https://x.org)")
        type(" on")
        #expect(editor.markdown == "go [https://x.org](https://x.org) on")
    }

    @Test func typedLinkMarkdownBecomesALink() {
        type("see [the *docs*](my notes.md) or [x](<my notes.md>) now")
        #expect(storage.string == "see [the docs](my notes.md) or x now")
        // A destination with a space needs angle brackets, so the first
        // isn't a link.
        #expect(editor.markdown == "see [the *docs*](my notes.md) or [x](<my notes.md>) now")
        type(" [a](b)")
        #expect(storage.string.hasSuffix("now a"))
        #expect(editor.markdown.hasSuffix("now [a](b)"))
    }

    @Test func loadsAndSavesLinksWithStyles() {
        let markdown = "**[a](x)** and [**b** c](<y z>) and [`d`](e)"
        editor.load(markdown: markdown)
        #expect(storage.string == "a and b c and d")
        #expect(editor.markdown == markdown)
    }

    @Test func codeBlocksArentLinked() {
        editor.load(markdown: "a\n```\ncode\n```")
        select(0, storage.length)
        step { editor.setLink("x", in: editor.linkTargetRange()) }
        #expect(editor.markdown == "[a](x)\n```\ncode\n```")
    }

    @Test func highlightTogglesTheSelectionInYellow() {
        type("one two")
        select(4, 3)
        step { editor.toggleHighlight(nil) }
        #expect(editor.markdown == "one ==two==")
        #expect(storage.attribute(.backgroundColor, at: 4, effectiveRange: nil) as? NSColor == InlineStyle.highlightColor)
        #expect(storage.attribute(.backgroundColor, at: 3, effectiveRange: nil) == nil)
        let item = NSMenuItem(title: "Highlight", action: #selector(EditorViewController.toggleHighlight(_:)), keyEquivalent: "")
        #expect(editor.validateMenuItem(item) && item.state == .on)
        step { editor.toggleHighlight(nil) }
        #expect(editor.markdown == "one two")
        #expect(storage.attribute(.backgroundColor, at: 4, effectiveRange: nil) == nil)
    }

    @Test func typedEqualsSignsBecomeHighlight() {
        type("a ==big deal== and x == y")
        #expect(storage.string == "a big deal and x == y")
        #expect(storage.inlineStyles(at: 2) == [.highlight])
        #expect(editor.markdown == "a ==big deal== and x == y")
    }

    @Test func hidesHTMLComments() {
        let markdown = "# Title\n<!-- hidden -->\ntext <!-- a *b* --> more\n<!--\n- multi\n# line\n-->\nend"
        editor.load(markdown: markdown)
        #expect(storage.string == "Title\n\u{FFFC}\ntext \u{FFFC} more\n\u{FFFC}\nend")
        #expect(editor.markdown == markdown)
        // Lines of only comments take no space; others are as usual.
        let layoutManager = textView.layoutManager!
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        func height(at index: Int) -> CGFloat {
            layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index), effectiveRange: nil).height
        }
        #expect(height(at: 6) < 1 && height(at: 21) < 1)
        #expect(height(at: 8) > 10)
        #expect(editor.plainText(for: NSRange(location: 0, length: storage.length)) == markdown)
    }

    @Test func hidesLeanpubHangingParagraphLines() {
        let markdown = "{begin-hanging-paragraphs}\n\n[1] One\n{end-hanging-paragraphs}\nSee {begin-hanging-paragraphs} here"
        editor.load(markdown: markdown)
        #expect(storage.string == "\u{FFFC}\n\n[1] One\n\u{FFFC}\nSee {begin-hanging-paragraphs} here")
        #expect(editor.markdown == markdown)
        #expect(editor.plainText(for: NSRange(location: 0, length: storage.length)) == markdown)
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        func height(at index: Int) -> CGFloat {
            layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index), effectiveRange: nil).height
        }
        #expect(height(at: 0) < 1 && height(at: 11) < 1)
        #expect(height(at: 3) > 10)
    }

    @Test func typedCommentsAreHidden() {
        type("a <!-- note --> b")
        #expect(storage.string == "a \u{FFFC} b")
        #expect(editor.markdown == "a <!-- note --> b")
    }

    @Test func linkButtonIsLeftOfTheImageButton() {
        editor.view.window!.layoutIfNeeded()
        #expect(editor.linkButton.frame.maxX < editor.imageButton.frame.minX)
        #expect(editor.linkButton.frame.minX > editor.superscriptButton.frame.maxX + 16)
    }

    @Test func subscriptAndSuperscriptButtonsAreLaidOutAfterCode() {
        editor.view.window!.layoutIfNeeded()
        #expect(editor.subscriptButton.frame.minX > editor.codeButton.frame.maxX)
        #expect(editor.superscriptButton.frame.minX > editor.subscriptButton.frame.maxX)
        #expect(editor.imageButton.frame.minX > editor.superscriptButton.frame.maxX + 50)
    }

    @Test func headerLayout() {
        let window = editor.view.window!
        window.layoutIfNeeded()
        #expect(editor.boldButton.frame.minX > editor.stylePopUp.frame.maxX)
        #expect(editor.italicButton.frame.minX > editor.boldButton.frame.maxX)
        #expect(editor.imageButton.frame.maxX < editor.viewModeControl.frame.minX)
        #expect(editor.strikethroughButton.frame.minX > editor.italicButton.frame.maxX)
        #expect(editor.imageButton.frame.minX > editor.strikethroughButton.frame.maxX + 100)

    }
}

/// Inline code and code blocks.
@MainActor
@Suite struct CodeTests {
    let document: MarkdownDocument
    let editor: EditorViewController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
    }

    private var textView: EditorTextView { editor.textView }
    private var storage: NSTextStorage { editor.storage }

    private func step(_ action: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        action()
        document.undoManager?.endUndoGrouping()
    }

    private func type(_ text: String) {
        for character in text {
            if character == "\n" {
                step { textView.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
            } else {
                step { textView.insertText(String(character), replacementRange: textView.selectedRange()) }
            }
        }
    }

    private func select(_ location: Int, _ length: Int = 0) {
        step { textView.setSelectedRange(NSRange(location: location, length: length)) }
    }

    private func font(at index: Int) -> NSFont {
        storage.attribute(.font, at: index, effectiveRange: nil) as! NSFont
    }

    @Test func showsAndSavesInlineCode() {
        let markdown = "run `ls *.md` and **`bold code`**"
        editor.load(markdown: markdown)
        #expect(storage.string == "run ls *.md and bold code")
        #expect(storage.inlineStyles(at: 4) == [.code])
        #expect(font(at: 4).isFixedPitch)
        #expect(!font(at: 0).isFixedPitch)
        #expect(storage.attribute(.backgroundColor, at: 4, effectiveRange: nil) != nil)
        #expect(storage.inlineStyles(at: 16) == [.bold, .code])
        #expect(editor.markdown == markdown)
    }

    @Test func codeButtonTogglesTheSelection() {
        type("call foo now")
        select(5, 3)
        step { editor.codeButton.performClick(nil) }
        #expect(editor.markdown == "call `foo` now")
        #expect(editor.codeButton.state == .on)
        step { editor.toggleCode(nil) }
        #expect(editor.markdown == "call foo now")
        #expect(storage.attribute(.backgroundColor, at: 5, effectiveRange: nil) == nil)
    }

    @Test func typedBackticksBecomeCodeAndItsTextStaysLiteral() {
        type("use `a*b*c` then *it*.")
        #expect(storage.string == "use a*b*c then it.")
        #expect(storage.inlineStyles(at: 5) == [.code])
        #expect(storage.inlineStyles(at: 15) == [.italic])
        #expect(editor.markdown == "use `a*b*c` then *it*.")
    }

    @Test func showsAndSavesCodeBlocks() {
        let markdown = "Before\n```swift\nlet x = 1\n# not a heading\n- **not bold**\n```\nAfter"
        editor.load(markdown: markdown)
        #expect(storage.string == "Before\nlet x = 1\n# not a heading\n- **not bold**\nAfter")
        #expect(storage.blockStyle(at: 7) == .code)
        #expect(storage.blockStyle(at: 33) == .code)
        #expect(font(at: 7).isFixedPitch)
        #expect(storage.blockStyle(at: storage.length - 1) == .paragraph)
        #expect(editor.markdown == markdown)
    }

    @Test func keepsNeighbouringBlocksApart() {
        let markdown = "```sh\na\n```\n```\nb\n```"
        editor.load(markdown: markdown)
        #expect(editor.markdown == markdown)
        // A new line at the start of a block stays in that block.
        select(0)
        type("\n")
        #expect(editor.markdown == "```sh\n\na\n```\n```\nb\n```")
    }

    @Test func codeStyleFromThePopup() {
        editor.load(markdown: "one **two**\nthree")
        select(0, storage.length)
        editor.stylePopUp.selectItem(withTag: BlockStyle.code.rawValue)
        step { editor.styleChosen(editor.stylePopUp) }
        #expect(editor.markdown == "```\none two\nthree\n```")
        #expect(editor.stylePopUp.selectedItem?.title == "Code")
        editor.stylePopUp.selectItem(withTag: BlockStyle.paragraph.rawValue)
        step { editor.styleChosen(editor.stylePopUp) }
        #expect(editor.markdown == "one two\nthree")
    }

    @Test func typingAFenceStartsABlockAndAnEmptyLineEndsIt() {
        type("Intro\n```python\nif x:\n    # comment\n\nOutro")
        #expect(editor.markdown == "Intro\n```python\nif x:\n    # comment\n```\nOutro")
        #expect(storage.blockStyle(at: 6) == .code)
    }

    @Test func markdownTypedInCodeStaysText() {
        type("```\n# a\n- b\n**c** `d` ![](e.png)")
        #expect(storage.string == "# a\n- b\n**c** `d` ![](e.png)")
        #expect(editor.markdown == "```\n# a\n- b\n**c** `d` ![](e.png)\n```")
    }

    @Test func inlineStyleButtonsSkipCodeBlocks() {
        editor.load(markdown: "text\n```\ncode\n```")
        select(0, storage.length)
        step { editor.toggleBold(nil) }
        #expect(editor.markdown == "**text**\n```\ncode\n```")
    }

    @Test func copiesWholeCodeLinesAsABlockAndPartsAsTyped() {
        editor.load(markdown: "a `b*`\n```swift\n*c*\n# d\n```\n````\n```\n````\ne")
        #expect(editor.plainText(for: NSRange(location: 0, length: storage.length))
            == "a `b*`\n```swift\n*c*\n# d\n```\n````\n```\n````\ne")
        // Part of a code line is as typed. The formatted text starts
        // "a b*\n*c*\n".
        #expect(editor.plainText(for: NSRange(location: 5, length: 2)) == "*c")
        #expect(editor.plainText(for: NSRange(location: 2, length: 7)) == "`b*`\n```swift\n*c*\n```\n")
    }

    @Test func menusAndButtons() {
        let menu = MainMenu.make()
        let code = menu.items.first { $0.title == "Format" }!.submenu!.items.first { $0.title == "Code" }!
        #expect(code.keyEquivalent == "e")
        let reload = menu.items.first { $0.title == "View" }!.submenu!.items.first { $0.title == "Reload Images" }!
        #expect(reload.keyEquivalent == "R")
        #expect(BlockStyle.allCases.map(\.title).contains("Code"))
        editor.view.window!.layoutIfNeeded()
        #expect(editor.codeButton.frame.minX > editor.strikethroughButton.frame.maxX)
        #expect(editor.imageButton.frame.minX > editor.codeButton.frame.maxX)
    }

    @Test func reloadImagesReadsTheFilesAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupReload-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        document.fileURL = folder.appendingPathComponent("doc.md")
        let image = folder.appendingPathComponent("pic.png")
        try ImageTests.writePNG(width: 40, height: 20, to: image)
        editor.load(markdown: "![](pic.png)")
        func size() -> NSSize? {
            ((storage.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?.attachmentCell
                as? ImageAttachmentCell)?.cellSize()
        }
        #expect(size() == NSSize(width: 40, height: 20))
        try ImageTests.writePNG(width: 60, height: 30, to: image)
        editor.reloadImages(nil)
        #expect(size() == NSSize(width: 60, height: 30))
        #expect(editor.markdown == "![](pic.png)")
        #expect(document.undoManager?.canUndo == false)

    }
}

/// Project windows: a folder's Markdown files in a sidebar, one shown at a
/// time, the others kept open.
@MainActor
@Suite struct ProjectTests {
    let folder: URL
    let project: ProjectWindowController

    init() throws {
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupProjectTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let manager = FileManager.default
        try manager.createDirectory(at: folder.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try manager.createDirectory(at: folder.appendingPathComponent("Pages.app"), withIntermediateDirectories: true)
        for (name, text) in [("b.md", "# B"), ("a.md", "A text"), ("notes/c.markdown", "C"), ("notes.txt", "x"),
                             (".hidden.md", "h"), ("picture.png", "p")] {
            try Data(text.utf8).write(to: folder.appendingPathComponent(name))
        }
        project = ProjectWindowController(root: folder)
        _ = project.sidebar.view
    }

    private func document(_ name: String) throws -> MarkdownDocument {
        let document = try MarkdownDocument(contentsOf: folder.appendingPathComponent(name),
                                            ofType: "net.daringfireball.markdown")
        document.undoManager?.groupsByEvent = false
        return document
    }

    /// Runs `action` as one edit of `document`, as an event would.
    private func step(_ document: MarkdownDocument, _ action: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        action()
        document.undoManager?.endUndoGrouping()
    }

    /// A narrow editor, as a split view restores it, shows the text below
    /// the header, rather than stretching the header's separator downwards.
    @Test func narrowSavedSplitStillShowsTheText() throws {
        let defaults = UserDefaults.standard
        let splitKey = "NSSplitView Subview Frames MarkupProjectSplit"
        let frameKey = "NSWindow Frame MarkupProject \(folder.standardizedFileURL.path)"
        let saved = defaults.object(forKey: splitKey)
        defer {
            defaults.set(saved, forKey: splitKey)
            defaults.removeObject(forKey: frameKey)
        }
        defaults.set(["0, 0, 408, 1395, NO, NO", "408, 0, 400, 1395, NO, NO"], forKey: splitKey)
        defaults.set("100 12 808 1395 0 0 3440 1410 ", forKey: frameKey)
        let project = ProjectWindowController(root: folder)
        let a = try document("a.md")
        project.show(a)
        project.showWindow(nil)
        project.window!.layoutIfNeeded()
        let scrollView = a.editor.textView.enclosingScrollView!
        #expect(!scrollView.hasAmbiguousLayout)
        #expect(scrollView.frame.height > 1000)
        project.close()
    }

    @Test func sidebarListsFoldersThenTextFiles() {
        let names = project.sidebar.rootNode.children.map(\.name)
        #expect(names == ["notes", "a.md", "b.md", "notes.txt"])
        #expect(project.sidebar.rootNode.children[0].children.map(\.name) == ["c.markdown"])
    }

    @Test func theProjectFolderIsAtTheTopAndOpensAndCloses() {
        let outline = project.sidebar.outlineView
        _ = project.sidebar.view
        let root = project.sidebar.rootNode
        #expect(outline.numberOfRows > 1)
        #expect(outline.item(atRow: 0) as? ProjectSidebarController.Node === root)
        #expect(outline.isItemExpanded(root))
        #expect(outline.parent(forItem: outline.item(atRow: 1)) as? ProjectSidebarController.Node === root)
        #expect(project.sidebar.node(for: folder) === root)
        outline.collapseItem(root)
        #expect(outline.numberOfRows == 1)
        // Following the folder on disk keeps it closed, or open.
        project.sidebar.reload()
        #expect(outline.numberOfRows == 1)
        outline.expandItem(project.sidebar.rootNode)
        project.sidebar.reload()
        #expect(outline.isItemExpanded(project.sidebar.rootNode))
    }

    @Test func theMenuIsForTheItemClicked() throws {
        let menu = try #require(project.sidebar.outlineView.menu)
        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["New File…", "New Folder…", "Duplicate", "Rename…", "Delete"])
        // Below the rows, it is for the project folder, which can't be
        // duplicated or deleted.
        project.sidebar.menuNeedsUpdate(menu)
        #expect(menu.items.allSatisfy { $0.isSeparatorItem || ($0.representedObject as? URL)?.path == folder.path })
        #expect(menu.items.allSatisfy { $0.isSeparatorItem || $0.target === project })
        let duplicate = menu.items.first { $0.title == "Duplicate" }!
        #expect(!project.validateMenuItem(duplicate))
        duplicate.representedObject = folder.appendingPathComponent("a.md")
        #expect(project.validateMenuItem(duplicate))
    }

    @Test func newFilesAndFoldersGoInTheFolderClicked() throws {
        let notes = folder.appendingPathComponent("notes")
        #expect(ProjectWindowController.folder(for: notes) == notes)
        #expect(ProjectWindowController.folder(for: notes.appendingPathComponent("c.markdown")).path == notes.path)
        #expect(ProjectWindowController.uniqueName("Untitled", extension: "md", in: notes) == "Untitled.md")
        let file = try project.createFile(named: " Chapter ", in: notes)
        #expect(file.lastPathComponent == "Chapter.md")
        #expect(try Data(contentsOf: file).isEmpty)
        #expect(project.sidebar.node(for: file) != nil)
        #expect(ProjectWindowController.uniqueName("Chapter", extension: "md", in: notes) == "Chapter 2.md")
        #expect(try project.createFile(named: "list.txt", in: notes).lastPathComponent == "list.txt")
        #expect(throws: ProjectWindowController.NameError.self) { try project.createFile(named: "Chapter.md", in: notes) }
        #expect(throws: ProjectWindowController.NameError.self) { try project.createFile(named: "a/b", in: notes) }
        #expect(throws: ProjectWindowController.NameError.self) { try project.createFile(named: " ", in: notes) }
        let made = try project.createFolder(named: "drafts", in: notes)
        #expect(ProjectWindowController.isFolder(made))
        #expect(project.sidebar.node(for: made)?.isFolder == true)
    }

    @Test func duplicatesAreNamedAsFinderNamesThem() throws {
        let a = folder.appendingPathComponent("a.md")
        #expect(try project.duplicate(a).lastPathComponent == "a copy.md")
        #expect(try project.duplicate(a).lastPathComponent == "a copy 2.md")
        #expect(try String(contentsOf: folder.appendingPathComponent("a copy.md"), encoding: .utf8) == "A text")
        let notes = try project.duplicate(folder.appendingPathComponent("notes"))
        #expect(notes.lastPathComponent == "notes copy")
        #expect(FileManager.default.fileExists(atPath: notes.appendingPathComponent("c.markdown").path))
    }

    @Test func renamingMovesTheDocumentsInside() throws {
        let c = try document("notes/c.markdown")
        let b = try document("b.md")
        project.show(b)
        project.show(c)
        step(c) { c.editor.textView.insertText("New ", replacementRange: NSRange(location: 0, length: 0)) }
        let renamed = try project.rename(folder.appendingPathComponent("notes"), to: "Notes 2026")
        #expect(renamed.lastPathComponent == "Notes 2026")
        #expect(c.fileURL?.path == folder.appendingPathComponent("Notes 2026/c.markdown").path)
        #expect(c.isDocumentEdited && c.editor.markdown == "New C")
        #expect(b.fileURL?.lastPathComponent == "b.md")
        #expect(project.sidebar.outlineView.row(forItem: project.sidebar.node(for: c.fileURL!))
            == project.sidebar.outlineView.selectedRow)
        // A file, and one changing only its case.
        #expect(try project.rename(folder.appendingPathComponent("a.md"), to: "Alpha.md").lastPathComponent == "Alpha.md")
        #expect(try project.rename(folder.appendingPathComponent("Alpha.md"), to: "alpha.md").lastPathComponent == "alpha.md")
        #expect(throws: ProjectWindowController.NameError.self) {
            try project.rename(folder.appendingPathComponent("alpha.md"), to: "b.md")
        }
    }

    @Test func deletingClosesTheDocumentsInside() throws {
        project.moveToTrash = { try FileManager.default.removeItem(at: $0) }
        let c = try document("notes/c.markdown")
        let b = try document("b.md")
        project.show(b)
        project.show(c)
        try project.trash(folder.appendingPathComponent("notes"))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("notes").path))
        #expect(project.documents.map { $0 === b } == [true])
        #expect(project.currentDocument == nil)
        #expect(project.sidebar.node(for: folder.appendingPathComponent("notes")) == nil)
    }

    @Test func showsOneFileAtATimeAndKeepsTheOthersEdits() throws {
        let a = try document("a.md"), b = try document("b.md")
        project.show(a)
        #expect(project.window?.title == "a.md")
        #expect(a.editor.view.superview != nil)

        a.undoManager?.beginUndoGrouping()
        a.editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
        a.editor.textView.insertText("!", replacementRange: a.editor.textView.selectedRange())
        a.undoManager?.endUndoGrouping()
        #expect(a.isDocumentEdited)
        #expect(project.window?.isDocumentEdited == true)
        let sidebar = project.sidebar.outlineView
        let row = sidebar.row(forItem: project.sidebar.node(for: folder.appendingPathComponent("a.md")))
        let cell = sidebar.view(atColumn: 0, row: row, makeIfNecessary: true) as? ProjectSidebarController.FileCell
        #expect(cell?.editedMark.isHidden == false)

        project.show(b)
        #expect(project.window?.title == "b.md")
        #expect(project.window?.isDocumentEdited == false)
        #expect(a.editor.view.superview == nil && b.editor.view.superview != nil)
        #expect(project.documents.count == 2)
        #expect(project.sidebar.outlineView.selectedRow == project.sidebar.outlineView.row(forItem:
            project.sidebar.node(for: folder.appendingPathComponent("b.md"))))

        project.show(a)
        #expect(a.currentMarkdown == "A text!")
        #expect(b.currentMarkdown == "# B")
    }

    @Test func documentActionsGoToTheFileShown() throws {
        let a = try document("a.md")
        project.show(a)
        #expect(project.supplementalTarget(forAction: #selector(NSDocument.save(_:)), sender: nil) as? MarkdownDocument === a)
        #expect(project.windowWillReturnUndoManager(project.window!) === a.undoManager)
    }

    @Test func selectingAFileInANestedFolderOpensTheFolder() throws {
        let c = try document("notes/c.markdown")
        project.show(c)
        let node = project.sidebar.node(for: folder.appendingPathComponent("notes/c.markdown"))
        #expect(project.sidebar.outlineView.row(forItem: node) == project.sidebar.outlineView.selectedRow)
    }

    @Test func textFilesOpenAsPlainText() throws {
        let notes = try document("notes.txt")
        project.show(notes)
        #expect(notes.isPlainText)
        #expect(notes.editor.textView.string == "x")
    }

    // Reopening the file goes through NSDocumentController, which can't open
    // documents here, because the test runner doesn't declare Markup's
    // document types.
    @Test func projectsOpenAtQuitOpenAgainAtLaunch() throws {
        let settings = Settings(defaults: UserDefaults(suiteName: "MarkupTests-\(UUID().uuidString)")!)
        let quitting = AppDelegate()
        quitting.settings = settings
        #expect(quitting.applicationShouldOpenUntitledFile(NSApp))
        quitting.openProject(at: folder).show(try document("notes/c.markdown"))
        quitting.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        quitting.projects.forEach { $0.window?.close() }
        let file = folder.appendingPathComponent("notes/c.markdown").standardizedFileURL
        #expect(settings.openProjects == [Settings.OpenProject(folder: folder.standardizedFileURL, file: file)])

        settings.openProjects = [Settings.OpenProject(folder: folder)]
        let launching = AppDelegate()
        launching.settings = settings
        #expect(!launching.applicationShouldOpenUntitledFile(NSApp))
        launching.reopenProjects()
        #expect(launching.projects.map(\.root) == [folder.standardizedFileURL])
        launching.projects.forEach { $0.window?.close() }
    }

    @Test func projectsWithNoFileShownReopenWithNone() throws {
        let settings = Settings(defaults: UserDefaults(suiteName: "MarkupTests-\(UUID().uuidString)")!)
        settings.openProjects = [Settings.OpenProject(folder: folder, file: folder.appendingPathComponent("gone.md"))]
        let delegate = AppDelegate()
        delegate.settings = settings
        delegate.reopenProjects()
        #expect(delegate.projects.count == 1)
        #expect(delegate.projects.first?.currentDocument == nil)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(settings.openProjects == [Settings.OpenProject(folder: folder.standardizedFileURL, file: nil)])
        delegate.projects.forEach { $0.window?.close() }
    }

    @Test func projectFoldersThatHaveGoneAreNotReopened() throws {
        let settings = Settings(defaults: UserDefaults(suiteName: "MarkupTests-\(UUID().uuidString)")!)
        settings.openProjects = [Settings.OpenProject(folder: folder.appendingPathComponent("gone"))]
        let delegate = AppDelegate()
        delegate.settings = settings
        #expect(delegate.applicationShouldOpenUntitledFile(NSApp))
        delegate.reopenProjects()
        #expect(delegate.projects.isEmpty)
    }

    @Test func closingWithNoUnsavedChangesClosesTheDocuments() throws {
        let a = try document("a.md")
        project.show(a)
        #expect(project.windowShouldClose(project.window!))
        project.window?.close()
        #expect(a.project == nil)
        #expect(project.documents.isEmpty)
    }
}

@MainActor
@Suite struct FindTests {
    @Test func findShowsTheFindBarAboveTheText() throws {
        _ = NSApplication.shared
        let document = MarkdownDocument()
        document.makeWindowControllers()
        let textView = document.editor.textView
        let find = try #require(MainMenu.make().items.first { $0.title == "Edit" }?.submenu?
            .items.first { $0.title == "Find" }?.submenu?.items.first)
        #expect(find.title == "Find…" && find.keyEquivalent == "f")
        #expect(textView.validateUserInterfaceItem(find))
        textView.performTextFinderAction(find)
        #expect(textView.enclosingScrollView?.isFindBarVisible == true)
    }
}

/// Files that aren't Markdown open as plain text, with no formatting.
@MainActor
@Suite struct PlainTextTests {
    let folder: URL
    static let sample = "# not a heading\n- not a list\n**not bold**\n"

    init() throws {
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupPlainTextTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func open(_ name: String, ofType typeName: String = "public.plain-text") throws -> MarkdownDocument {
        let url = folder.appendingPathComponent(name)
        try Data(Self.sample.utf8).write(to: url)
        let document = try MarkdownDocument(contentsOf: url, ofType: typeName)
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        return document
    }

    @Test func textFilesArePlainTextAndMarkdownFilesAreNot() throws {
        #expect(try open("notes.txt").isPlainText)
        #expect(try open("README").isPlainText)
        // Another app's type for .md files reaches the document as plain text.
        #expect(try !open("notes.md").isPlainText)
        #expect(try !open("notes.MARKDOWN", ofType: "net.daringfireball.markdown").isPlainText)
        #expect(!MarkdownDocument().isPlainText)
    }

    @Test func showsTheTextAsItIsWithNoFormattingControls() throws {
        let editor = try open("notes.txt").editor
        #expect(editor.textView.string == Self.sample)
        #expect(editor.isShowingMarkdown)
        #expect(!editor.plainTextLabel.isHidden)
        for control in [editor.stylePopUp, editor.boldButton, editor.linkButton, editor.imageButton,
                        editor.viewModeControl] as [NSView] {
            #expect(control.isHidden)
        }
    }

    @Test func markdownFilesHaveNoPlainTextLabel() throws {
        #expect(try open("notes.md").editor.plainTextLabel.isHidden)
    }

    @Test func typedMarkdownStaysAsTyped() throws {
        let document = try open("notes.txt")
        let textView = document.editor.textView
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        for character in "## *a* - [ ] b" {
            document.undoManager?.beginUndoGrouping()
            textView.insertText(String(character), replacementRange: textView.selectedRange())
            document.undoManager?.endUndoGrouping()
        }
        let data = try document.data(ofType: "public.plain-text")
        #expect(String(decoding: data, as: UTF8.self) == Self.sample + "## *a* - [ ] b")
    }

    @Test func cannotSwitchToTheFormattedView() throws {
        let editor = try open("notes.txt").editor
        let item = NSMenuItem(title: "Show Markdown", action: #selector(EditorViewController.toggleMarkdown(_:)), keyEquivalent: "")
        #expect(!editor.validateMenuItem(item))
        editor.toggleMarkdown(item)
        #expect(editor.isShowingMarkdown)
        #expect(editor.textView.string == Self.sample)
    }

    @Test func copiesTheTextAsItIs() throws {
        let editor = try open("notes.txt").editor
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MarkupPlainTextTests-\(UUID().uuidString)"))
        editor.textView.setSelectedRange(NSRange(location: 0, length: editor.textView.string.utf16.count))
        _ = editor.textView.writeSelection(to: pasteboard, type: .string)
        #expect(pasteboard.string(forType: .string) == Self.sample)
    }

    @Test func printsTheTextAsItIs() throws {
        let operation = try open("notes.txt").printOperation(withSettings: [:])
        let text = try #require((operation.view as? NSTextView)?.textStorage)
        #expect(text.string == Self.sample)
    }
}

/// Tables: shown as a grid of cells, saved as Markdown tables.
@MainActor
@Suite struct TableTests {
    let document: MarkdownDocument
    let editor: EditorViewController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
    }

    private var textView: EditorTextView { editor.textView }
    private var storage: NSTextStorage { editor.storage }

    private func step(_ action: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        action()
        document.undoManager?.endUndoGrouping()
    }

    private func type(_ text: String) {
        for character in text {
            if character == "\n" {
                press(#selector(NSResponder.insertNewline(_:)))
            } else {
                step { textView.insertText(String(character), replacementRange: textView.selectedRange()) }
            }
        }
    }

    private func press(_ command: Selector) {
        step { textView.doCommand(by: command) }
    }

    private func insertTable(columns: Int) {
        let controller = editor.makeTableSizeController()
        controller.loadView()
        controller.columns = columns
        step { controller.insert(nil) }
    }

    private func isBold(at location: Int) -> Bool {
        (storage.attribute(.font, at: location, effectiveRange: nil) as! NSFont).fontDescriptor.symbolicTraits.contains(.bold)
    }

    private func cell(at location: Int) -> (row: Int, column: Int)? {
        editor.tableBlock(at: location).map { ($0.startingRow, $0.startingColumn) }
    }

    private var selectedText: String {
        (textView.string as NSString).substring(with: textView.selectedRange())
    }

    static let sample = "| Name | Count |\n| --- | --: |\n| **one** | 1 |"

    @Test func showsTheTableAsAGridAndSavesItAsMarkdown() {
        editor.load(markdown: Self.sample)
        #expect(textView.string == "Name\nCount\none\n1\n")
        let block = editor.tableBlock(at: 0)
        #expect(block?.table.numberOfColumns == 2)
        #expect(block?.backgroundColor != nil)
        #expect(cell(at: 5)! == (0, 1) && cell(at: 11)! == (1, 0) && cell(at: 15)! == (1, 1))
        #expect(editor.tableBlock(at: 11)?.table === block?.table)
        #expect(isBold(at: 0) && isBold(at: 11) && storage.attribute(.inlineBold, at: 11, effectiveRange: nil) != nil)
        #expect(!isBold(at: 15))
        #expect((storage.attribute(.paragraphStyle, at: 15, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .right)
        #expect(editor.markdown == "| Name    | Count |\n| ------- | ----: |\n| **one** | 1     |\n")
    }

    @Test func tableButtonIsNextToTheLinkButton() {
        #expect(editor.tableButton.superview === editor.headerView)
        #expect(editor.tableButton.action == #selector(EditorViewController.insertTable(_:)))
    }

    @Test func tablePopoverAsksForTheNumberOfColumns() {
        var inserted: [Int] = []
        let controller = TableSizeController(columns: 3) { inserted.append($0) }
        controller.loadView()
        #expect(controller.field.integerValue == 3 && controller.stepper.integerValue == 3)
        controller.stepper.integerValue = 4
        _ = controller.stepper.target?.perform(controller.stepper.action, with: controller.stepper)
        #expect(controller.field.integerValue == 4)
        let fieldEditor = NSTextView()
        fieldEditor.string = "6"
        #expect(controller.control(controller.field, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(controller.columns == 7 && controller.stepper.integerValue == 7)
        fieldEditor.string = "1"
        #expect(controller.control(controller.field, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(controller.columns == 1)
        controller.columns = 99
        #expect(controller.columns == 20)
        controller.columns = 5
        controller.insert(nil)
        #expect(inserted == [5])
        #expect(controller.insertButton.keyEquivalent == "\r")
    }

    @Test func tablePopoverRemembersTheLastNumberOfColumns() {
        let saved = EditorViewController.tableColumns
        defer { EditorViewController.tableColumns = saved }
        insertTable(columns: 4)
        #expect(EditorViewController.tableColumns == 4)
        #expect(editor.makeTableSizeController().columns == 4)
    }

    @Test func insertsATableWithTheCaretInTheFirstCell() {
        insertTable(columns: 3)
        #expect(textView.string == "\n\n\n\n\n\n")
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
        #expect(cell(at: 5)! == (1, 2))
        #expect(editor.markdown == "|     |     |     |\n| --- | --- | --- |\n|     |     |     |\n")
        type("Name")
        #expect(isBold(at: 0) && cell(at: 0)! == (0, 0))
        #expect(editor.markdown.hasPrefix("| Name |     |     |\n| ---- |"))
        #expect(!editor.stylePopUp.isEnabled)
    }

    @Test func insertsBelowALineWithText() {
        editor.load(markdown: "Intro\nAfter")
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        insertTable(columns: 1)
        #expect(textView.string == "Intro\n\n\nAfter")
        #expect(editor.markdown == "Intro\n|     |\n| --- |\n|     |\nAfter")
        document.undoManager?.undo()
        #expect(textView.string == "Intro\nAfter")
    }

    @Test func tabMovesBetweenCellsAndAddsARowAtTheEnd() {
        insertTable(columns: 2)
        for text in ["A", "B", "1", "2"] {
            type(text)
            press(#selector(NSResponder.insertTab(_:)))
        }
        type("3")
        #expect(editor.markdown == "| A   | B   |\n| --- | --- |\n| 1   | 2   |\n| 3   |     |\n")
    }

    @Test func shiftTabSelectsThePreviousCell() {
        editor.load(markdown: "| a | b |\n|---|---|\n| c | d |")
        textView.setSelectedRange(NSRange(location: 4, length: 0))  // "|c"
        press(#selector(NSResponder.insertBacktab(_:)))
        #expect(selectedText == "b")
        press(#selector(NSResponder.insertBacktab(_:)))
        press(#selector(NSResponder.insertBacktab(_:)))
        #expect(selectedText == "a")
    }

    @Test func returnAddsARowAndInAnEmptyLastRowEndsTheTable() {
        editor.load(markdown: "| a |\n|---|\n| b |")
        press(#selector(NSResponder.insertNewline(_:)))
        #expect(editor.markdown == "| a   |\n| --- |\n|     |\n| b   |\n")
        #expect(textView.selectedRange().location == 2)
        document.undoManager?.undo()
        #expect(textView.string == "a\nb\n")
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        press(#selector(NSResponder.insertNewline(_:)))
        press(#selector(NSResponder.insertNewline(_:)))
        type("Text")
        #expect(editor.tableBlock(at: 4) == nil)
        #expect(editor.markdown == "| a   |\n| --- |\n| b   |\nText\n")
    }

    @Test func cellsCannotBeMergedOrSplit() {
        editor.load(markdown: "Intro\n| a | b |\n|-|-|")
        textView.setSelectedRange(NSRange(location: 8, length: 0))  // "|b"
        step { textView.deleteBackward(nil) }
        textView.setSelectedRange(NSRange(location: 6, length: 0))  // "|a"
        step { textView.deleteBackward(nil) }
        #expect(textView.string == "Intro\na\nb\n")
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        step { textView.insertText("x\ny", replacementRange: textView.selectedRange()) }
        #expect(textView.string == "Intro\nax y\nb\n")
    }

    @Test func deletingAcrossCellsEmptiesThem() {
        editor.load(markdown: "| a | b |\n|-|-|\n| c | d |")
        textView.setSelectedRange(NSRange(location: 2, length: 3))  // "b\nc"
        step { textView.deleteBackward(nil) }
        #expect(textView.string == "a\n\n\nd\n")
        #expect(editor.markdown == "| a   |     |\n| --- | --- |\n|     | d   |\n")
    }

    @Test func deletingATableWithTheTextAroundItRemovesIt() {
        editor.load(markdown: "Intro\n| a | b |\n|-|-|\nEnd")
        textView.setSelectedRange(NSRange(location: 2, length: 8))  // "tro\na\nb\n"
        step { textView.deleteBackward(nil) }
        #expect(editor.markdown == "InEnd")
    }

    @Test func cellsTakeInlineStyles() {
        editor.load(markdown: "| a | b |\n|-|-|")
        textView.setSelectedRange(NSRange(location: 0, length: 1))
        step { editor.toggleBold(nil) }
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        type("*i* x")
        #expect(editor.markdown == "| **a** | *i* xb |\n| ----- | ------ |\n")
    }

    @Test func typedOrPastedMarkdownTablesBecomeTables() {
        type("| a | b |\n|---|---|\n")
        #expect(textView.string == "a\nb\n\n\n")
        #expect(cell(at: 4)! == (1, 0))
        #expect(textView.selectedRange().location == 4)
        #expect(editor.markdown == "| a   | b   |\n| --- | --- |\n|     |     |\n")

        textView.setSelectedRange(NSRange(location: storage.length, length: 0))
        step { textView.insertText("\n| x |\n| - |\n| 1 |\n", replacementRange: textView.selectedRange()) }
        #expect(editor.markdown.hasSuffix("\n\n| x   |\n| --- |\n| 1   |\n"))
    }

    @Test func copyingATableWritesItsMarkdown() {
        editor.load(markdown: "Intro\n" + Self.sample)
        textView.setSelectedRange(NSRange(location: 0, length: storage.length))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MarkupTableTests-\(UUID().uuidString)"))
        _ = textView.writeSelection(to: pasteboard, type: .string)
        #expect(pasteboard.string(forType: .string) == "Intro\n| Name    | Count |\n| ------- | ----: |\n| **one** | 1     |\n")
        textView.setSelectedRange(NSRange(location: 6, length: 2))
        _ = textView.writeSelection(to: pasteboard, type: .string)
        #expect(pasteboard.string(forType: .string) == "Na")
    }

    @Test func switchingViewsKeepsTheCaretInItsRow() {
        editor.load(markdown: "Intro\n| a | b |\n|-|-|\n| c | d |\nEnd")
        textView.setSelectedRange(NSRange(location: 12, length: 0))  // "|d"
        editor.setShowingMarkdown(true)
        #expect(textView.string == "Intro\n| a   | b   |\n| --- | --- |\n| c   | d   |\nEnd")
        #expect(textView.selectedRange().location == 34)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count - 1, length: 0))  // "En|d"
        editor.setShowingMarkdown(false)
        #expect(textView.selectedRange().location == 16)
    }

    @Test func printsTheGrid() throws {
        editor.load(markdown: Self.sample)
        let printed = try #require((try document.printOperation(withSettings: [:]).view as? NSTextView)?.textStorage)
        #expect(printed.string == "Name\nCount\none\n1\n")
        #expect((printed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.isEmpty == false)
    }

    @Test func tableButtonIsOffInTheMarkdownView() {
        editor.setShowingMarkdown(true)
        #expect(!editor.tableButton.isEnabled)
        let item = NSMenuItem(title: "Table…", action: #selector(EditorViewController.insertTable(_:)), keyEquivalent: "")
        #expect(!editor.validateMenuItem(item))
    }
}

/// Front matter: hidden in the formatted view, with a badge in the header.
@MainActor
@Suite struct FrontMatterEditorTests {
    let document: MarkdownDocument
    let editor: EditorViewController

    static let markdown = "---\nlayout: post\ntitle: *Stacey's*\n---\n\n# Stacey's\nText"

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
        editor.load(markdown: Self.markdown)
    }

    private var textView: NSTextView { editor.textView }

    private func step(_ action: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        action()
        document.undoManager?.endUndoGrouping()
    }

    @Test func isHiddenAndSavedAsWritten() {
        #expect(textView.string == "\nStacey's\nText")
        #expect(editor.markdown == Self.markdown)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        step { textView.insertText(" more", replacementRange: textView.selectedRange()) }
        #expect(editor.markdown == Self.markdown + " more")
    }

    @Test func theBadgeShowsInTheFormattedViewOnly() {
        #expect(!editor.frontMatterBadge.isHidden)
        #expect(editor.frontMatterBadge.toolTip == "layout: post\ntitle: *Stacey's*\n\nClick to edit it in the Markdown view.")
        editor.setShowingMarkdown(true)
        #expect(editor.frontMatterBadge.isHidden)
        #expect(textView.string == Self.markdown)
        editor.setShowingMarkdown(false)
        #expect(!editor.frontMatterBadge.isHidden)
        editor.load(markdown: "Text")
        #expect(editor.frontMatterBadge.isHidden)
        #expect(editor.markdown == "Text")
    }

    @Test func theBadgeOpensTheMarkdownViewAtTheFrontMatter() {
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.frontMatterBadge.performClick(nil)
        #expect(editor.isShowingMarkdown)
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func switchingViewsKeepsTheCaretsLine() {
        // "Text", two characters in.
        textView.setSelectedRange(NSRange(location: 12, length: 0))
        editor.setShowingMarkdown(true)
        #expect(textView.selectedRange().location == (Self.markdown as NSString).length - 2)
        // Into the front matter, then back: the formatted text's start.
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        editor.setShowingMarkdown(false)
        #expect(textView.selectedRange().location == 0)
    }

    @Test func editingItInTheMarkdownViewKeepsTheEdit() {
        editor.setShowingMarkdown(true)
        step { textView.insertText("date: 2026\n", replacementRange: NSRange(location: 4, length: 0)) }
        editor.setShowingMarkdown(false)
        #expect(textView.string == "\nStacey's\nText")
        #expect(editor.markdown == "---\ndate: 2026\nlayout: post\ntitle: *Stacey's*\n---\n\n# Stacey's\nText")
    }

    @Test func frontMatterEndingTheFileGetsANewlineBeforeText() {
        editor.load(markdown: "---\na: 1\n---")
        #expect(textView.string.isEmpty)
        #expect(editor.markdown == "---\na: 1\n---")
        step { textView.insertText("Text", replacementRange: NSRange(location: 0, length: 0)) }
        #expect(editor.markdown == "---\na: 1\n---\nText")
    }

    @Test func isLeftOutOfPrinting() throws {
        let operation = try document.printOperation(withSettings: [:])
        #expect((operation.view as? NSTextView)?.string == "\nStacey's\nText")
    }
}

/// HTML tags the formatted view shows: <br>, <img>, <p> and </p>.
@MainActor
@Suite struct HTMLTagEditorTests {
    let document: MarkdownDocument
    let editor: EditorViewController
    let suiteName = "MarkupTests-\(UUID().uuidString)"
    let site: URL

    init() throws {
        _ = NSApplication.shared
        site = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupSite-\(UUID())")
        try FileManager.default.createDirectory(at: site.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: site.appendingPathComponent("_posts"), withIntermediateDirectories: true)
        try ImageTests.writePNG(width: 40, height: 20, to: site.appendingPathComponent("assets/pie.png"))

        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
        editor.settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        document.fileURL = site.appendingPathComponent("_posts/2026-10-09-staceys.md")
    }

    private func cleanUp() {
        editor.settings.defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: site)
    }

    private var textView: NSTextView { editor.textView }

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

    @Test func aLineBreakInsideALineBreaksIt() {
        defer { cleanUp() }
        editor.load(markdown: "One<br>two<BR />three")
        #expect(textView.string == "One\u{2028}two\u{2028}three")
        #expect(editor.markdown == "One<br>two<BR />three")
        // Still one line.
        #expect(editor.lineRange(at: 0).length == textView.string.utf16.count)
    }

    @Test func aLineBreakEndingALineIsHidden() {
        defer { cleanUp() }
        editor.load(markdown: "**Stacey's**<br>\nTel: 01268<br> \nCards.")
        #expect(textView.string == "Stacey's\u{FFFC}\nTel: 01268\u{FFFC} \nCards.")
        #expect(editor.markdown == "**Stacey's**<br>\nTel: 01268<br> \nCards.")
    }

    @Test func paragraphTagsAreHiddenAndLinesOfThemTakeNoSpace() {
        defer { cleanUp() }
        editor.load(markdown: "<p>\nText <p class=\"x\">here</p>\n</p>")
        #expect(textView.string == "\u{FFFC}\nText \u{FFFC}here\u{FFFC}\n\u{FFFC}")
        let style = textView.textStorage!.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style === HTMLComment.hiddenLineStyle)
        #expect(editor.markdown == "<p>\nText <p class=\"x\">here</p>\n</p>")
    }

    @Test func anImageShowsFromTheSitesRoot() throws {
        defer { cleanUp() }
        let html = #"<img src="/assets/pie.png" style="float:right; margin:20px;" alt="Pie">"#
        editor.load(markdown: "Before " + html + " after")
        let attachment = try #require(textView.textStorage!.attribute(.attachment, at: 7, effectiveRange: nil) as? NSTextAttachment)
        #expect((attachment.attachmentCell as? ImageAttachmentCell)?.picture != nil)
        #expect(editor.markdown == "Before " + html + " after")
        // Reloading reads it again.
        editor.reloadImages(nil)
        #expect(editor.markdown == "Before " + html + " after")
    }

    @Test func typedTagsConvertAndUndo() {
        defer { cleanUp() }
        editor.load(markdown: "")
        type("a<br>b")
        #expect(textView.string == "a\u{2028}b")
        #expect(editor.markdown == "a<br>b")
        document.undoManager?.undo()
        #expect(editor.markdown == "a<br>")
        editor.load(markdown: "")
        type("Line<br>")
        #expect(textView.string == "Line\u{FFFC}")
        #expect(editor.markdown == "Line<br>")
    }

    @Test func aLineBreakFollowsTheTextAfterIt() {
        defer { cleanUp() }
        editor.load(markdown: "One<br>two")
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        for _ in 0..<3 { step { textView.deleteBackward(nil) } }
        #expect(textView.string == "One\u{FFFC}")
        #expect(textView.selectedRange().location == 4)
        // Undoing the last deletion brings back the break with the "t".
        document.undoManager?.undo()
        #expect(textView.string == "One\u{2028}t")
        #expect(editor.markdown == "One<br>t")
    }

    private func font(at location: Int) -> NSFont {
        textView.textStorage!.attribute(.font, at: location, effectiveRange: nil) as! NSFont
    }

    @Test func formattingTagsFormatTheTextBetweenThem() {
        defer { cleanUp() }
        let markdown = "<h4>Title</h4>\nSome <strong>bold</strong>, <em>italic</em> and <b><i>both</i></b>."
        editor.load(markdown: markdown)
        #expect(textView.string == "\u{FFFC}Title\u{FFFC}\nSome \u{FFFC}bold\u{FFFC}, \u{FFFC}italic\u{FFFC} and \u{FFFC}\u{FFFC}both\u{FFFC}\u{FFFC}.")
        #expect(font(at: 1).pointSize == BlockStyle.heading4.font.pointSize)
        #expect(font(at: 1).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(textView.textStorage!.blockStyle(at: 1) == .paragraph)
        // The second line starts at 8: "Some " then the tag at 13.
        #expect(font(at: 14).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(!font(at: 9).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(font(at: 23).fontDescriptor.symbolicTraits.contains(.italic))
        let both = font(at: 37).fontDescriptor.symbolicTraits
        #expect(both.contains(.bold) && both.contains(.italic))
        // Saved exactly as written, with no Markdown added.
        #expect(editor.markdown == markdown)
        #expect(editor.plainText(for: NSRange(location: 13, length: 6)) == "<strong>bold</strong>")
    }

    @Test func editsKeepTheFormatsFollowingTheTags() {
        defer { cleanUp() }
        editor.load(markdown: "A <strong>b</strong> c")
        // Typed inside, the text is bold too.
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        type("ig")
        #expect(font(at: 5).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(editor.markdown == "A <strong>big</strong> c")
        // Without its closing tag, it isn't; undo brings both back.
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        step { textView.deleteBackward(nil) }
        #expect(!font(at: 3).fontDescriptor.symbolicTraits.contains(.bold))
        document.undoManager?.undo()
        #expect(font(at: 3).fontDescriptor.symbolicTraits.contains(.bold))
        #expect(editor.markdown == "A <strong>big</strong> c")
        // Typed tags format what they enclose.
        editor.load(markdown: "")
        type("x <em>y</em>")
        #expect(textView.string == "x \u{FFFC}y\u{FFFC}")
        #expect(font(at: 3).fontDescriptor.symbolicTraits.contains(.italic))
        #expect(editor.markdown == "x <em>y</em>")
    }

    @Test func otherHTMLStaysText() {
        defer { cleanUp() }
        editor.load(markdown: "<span>x</span> \\<br> <div>")
        #expect(textView.string == "<span>x</span> \\<br> <div>")
        #expect(editor.markdown == "<span>x</span> \\<br> <div>")
    }

    @Test func copyingWritesTheTagsBack() {
        defer { cleanUp() }
        editor.load(markdown: "One<br>two")
        #expect(editor.plainText(for: NSRange(location: 0, length: 7)) == "One<br>two")
    }
}

/// Copying and pasting in the formatted view: the pasteboard has the
/// selection's Markdown, and pasting it converts it back.
@MainActor
@Suite struct CopyPasteTests {
    let document: MarkdownDocument
    let editor: EditorViewController
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("MarkupTests-\(UUID().uuidString)"))

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
    }

    private var textView: NSTextView { editor.textView }

    private func step(_ action: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        action()
        document.undoManager?.endUndoGrouping()
    }

    /// Copies `range` as the Copy command does, onto the test's pasteboard.
    private func copy(_ range: NSRange) -> String? {
        pasteboard.clearContents()
        textView.setSelectedRange(range)
        _ = textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes)
        return pasteboard.string(forType: .string)
    }

    /// Pastes the test's pasteboard at `range`, as the Paste command does.
    private func paste(at range: NSRange) {
        textView.setSelectedRange(range)
        step { _ = textView.readSelection(from: pasteboard) }
    }

    private var everything: NSRange { NSRange(location: 0, length: textView.string.utf16.count) }

    @Test(arguments: ["Some **bold**, *italic* and ***both*** text", "# Heading", "## Sub", "- one\n  - two\n- [x] done",
                      "1. one\n2. two", "A [link](https://example.org) here", "~~strike~~ `code` H~2~O x^2^ ==mark==",
                      "> a quote", "```swift\nlet x = 1 // *not* emphasis\n# not a heading\n```",
                      "Before\n```\ncode\n```\nAfter", "| a | b |\n| - | - |\n| 1 | 2 |\n"])
    func formattingSurvivesCopyAndPaste(markdown: String) {
        defer { pasteboard.releaseGlobally() }
        editor.load(markdown: markdown)
        // As the editor writes it, which reformats a table.
        let expected = editor.markdown
        _ = copy(everything)
        editor.load(markdown: "")
        paste(at: NSRange(location: 0, length: 0))
        #expect(editor.markdown == expected)
    }

    @Test func theCopyIsMarkdown() {
        defer { pasteboard.releaseGlobally() }
        editor.load(markdown: "- **one**\n- two")
        #expect(copy(everything) == "- **one**\n- two")
    }

    @Test func aCodeBlockPastedInsideALineGoesOnLinesOfItsOwn() {
        defer { pasteboard.releaseGlobally() }
        editor.load(markdown: "```\n*x*\n```")
        _ = copy(everything)
        editor.load(markdown: "Hello World")
        paste(at: NSRange(location: 6, length: 0))
        #expect(editor.markdown == "Hello \n```\n*x*\n```\nWorld")
        document.undoManager?.undo()
        #expect(editor.markdown == "Hello World")
        // At the end of a line, the line after stays as it was.
        editor.load(markdown: "Hello\nWorld")
        paste(at: NSRange(location: 5, length: 0))
        #expect(editor.markdown == "Hello\n```\n*x*\n```\nWorld")
    }

    @Test func aCodeBlockPastedIntoCodeIsItsLines() {
        defer { pasteboard.releaseGlobally() }
        editor.load(markdown: "```\none\ntwo\n```")
        _ = copy(NSRange(location: 4, length: 3))
        #expect(pasteboard.string(forType: .string) == "```\ntwo\n```")
        paste(at: NSRange(location: 3, length: 0))
        #expect(editor.markdown == "```\nonetwo\ntwo\n```")
    }
}
