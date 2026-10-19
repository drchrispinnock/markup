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

/// Typing "# ", "## " or "### " at the start of a line.
@MainActor
@Suite struct HeadingShortcutTests {
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

    private func fontSize(at location: Int) -> CGFloat {
        (textView.textStorage!.attribute(.font, at: location, effectiveRange: nil) as! NSFont).pointSize
    }

    private var selectedStyle: BlockStyle? {
        BlockStyle(rawValue: editor.stylePopUp.selectedTag())
    }

    @Test(arguments: [("# ", BlockStyle.heading), ("## ", .subheading), ("### ", .subsubheading)])
    func markerAndSpaceMakeAHeading(marker: String, style: BlockStyle) {
        type(marker)
        #expect(textView.string == "")
        #expect(selectedStyle == style)
        type("Title")
        #expect(textView.string == "Title")
        #expect(fontSize(at: 0) == style.font.pointSize)
        #expect(editor.markdown == marker + "Title")
    }

    @Test func returnAfterATypedHeadingGoesBackToParagraph() {
        type("Intro")
        press(#selector(NSResponder.insertNewline(_:)))
        type("# Title")
        press(#selector(NSResponder.insertNewline(_:)))
        type("Body")
        #expect(editor.markdown == "Intro\n# Title\nBody")
    }

    @Test(arguments: ["#Title", "#### Four", "a # b", " # Indented"])
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
        #expect(selectedStyle == .heading)
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
        let item = NSMenuItem(title: "Show Markdown", action: #selector(EditorWindowController.toggleMarkdown(_:)), keyEquivalent: "")
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
        let textView = (document.windowControllers.first as! EditorWindowController).textView
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
    let editor: EditorWindowController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.makeWindowControllers()
        editor = document.windowControllers.first as! EditorWindowController
    }

    private func expectTextFitsWindow() {
        let window = editor.window!
        window.layoutIfNeeded()
        let clipView = editor.textView.enclosingScrollView!.contentView
        #expect(editor.textView.frame.width == clipView.bounds.width)
        #expect(editor.textView.frame.width <= window.contentView!.bounds.width)
    }

    @Test func textViewIsAsWideAsTheWindow() {
        expectTextFitsWindow()
    }

    @Test func textViewFollowsTheWindowWhenResized() {
        let window = editor.window!
        window.setContentSize(NSSize(width: 520, height: 400))
        expectTextFitsWindow()
        window.setContentSize(NSSize(width: 1100, height: 700))
        expectTextFitsWindow()
    }

    /// Including a heading, a list item and a word too long for one line.
    @Test func longLinesWrap() {
        editor.load(markdown: "# " + String(repeating: "heading ", count: 40) + "\n"
            + "- " + String(repeating: "item ", count: 80) + "\n"
            + String(repeating: "x", count: 400))
        editor.window!.setContentSize(NSSize(width: 520, height: 400))
        editor.window!.layoutIfNeeded()
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
    let editor: EditorWindowController
    static let sample = "# Title\n\nSome text.\n\n- one\n  - [x] done\n"

    init() throws {
        _ = NSApplication.shared
        document = MarkdownDocument()
        try document.read(from: Data(Self.sample.utf8), ofType: "net.daringfireball.markdown")
        document.makeWindowControllers()
        editor = document.windowControllers.first as! EditorWindowController
    }

    private func printedText() throws -> NSTextStorage {
        let operation = try document.printOperation(withSettings: [:])
        return try #require((operation.view as? NSTextView)?.textStorage)
    }

    @Test func printsTheFormattedText() throws {
        let text = try printedText()
        #expect(text.string == "Title\n\nSome text.\n\n\u{FFFC}one\n\u{FFFC}done\n")
        #expect(text.blockStyle(at: 0) == .heading)
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
    let editor: EditorWindowController
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
        editor = document.windowControllers.first as! EditorWindowController
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
        #expect(storage.blockStyle(at: 2) == .heading)
        #expect(cell(at: 12)?.picture != nil)
        #expect(cell(at: 27)?.picture == nil)
        #expect(cell(at: 27)?.path == "nope.png")
        #expect(editor.markdown == markdown)
    }

    @Test func looksInTheDocumentsFolderBeforeTheImagesDirectory() throws {
        defer { cleanUp() }
        let documentFolder = imagesDirectory.appendingPathComponent("doc")
        try FileManager.default.createDirectory(at: documentFolder.appendingPathComponent("cats"), withIntermediateDirectories: true)
        try Self.writePNG(width: 10, height: 10, to: documentFolder.appendingPathComponent("cats/tom.png"))
        document.fileURL = documentFolder.appendingPathComponent("post.md")
        #expect(editor.imageFolders.map(\.path) == [documentFolder.path, imagesDirectory.path])
        #expect(MarkdownImage(alt: "", path: "cats/tom.png").fileURL(in: editor.imageFolders)
            == documentFolder.appendingPathComponent("cats/tom.png"))
        try FileManager.default.removeItem(at: documentFolder.appendingPathComponent("cats/tom.png"))
        #expect(MarkdownImage(alt: "", path: "cats/tom.png").fileURL(in: editor.imageFolders)
            == imagesDirectory.appendingPathComponent("cats/tom.png"))
        #expect(MarkdownImage(alt: "", path: "cats%2Ftom.png").fileURL(in: editor.imageFolders) != nil)
        #expect(MarkdownImage(alt: "", path: "https://example.com/a.png").fileURL(in: editor.imageFolders) == nil)
    }

    @Test func largeImagesShrinkToTheTextWidth() throws {
        defer { cleanUp() }
        editor.load(markdown: "![](cats/tom.png)")
        let image = try #require(cell(at: 0))
        #expect(image.cellSize() == NSSize(width: 2000, height: 1000))
        let frame = image.cellFrame(for: textView.textContainer!, proposedLineFragment: NSRect(x: 0, y: 0, width: 502, height: 20),
                                    glyphPosition: .zero, characterIndex: 0)
        #expect(frame.size == NSSize(width: 500, height: 250))
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

    @Test func pathsAreRelativeToTheImagesDirectoryOnly() {
        defer { cleanUp() }
        let file = imagesDirectory.appendingPathComponent("cats/tom.png")
        #expect(EditorWindowController.path(of: file, relativeTo: imagesDirectory) == "cats/tom.png")
        #expect(EditorWindowController.path(of: imagesDirectory, relativeTo: imagesDirectory) == nil)
        #expect(EditorWindowController.path(of: URL(fileURLWithPath: "/etc/hosts"), relativeTo: imagesDirectory) == nil)
        let sibling = URL(fileURLWithPath: imagesDirectory.path + "-other/a.png")
        #expect(EditorWindowController.path(of: sibling, relativeTo: imagesDirectory) == nil)
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
