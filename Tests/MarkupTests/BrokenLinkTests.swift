import AppKit
import MarkupCore
import Testing
@testable import Markup

/// Links to headings that aren't there: marked where they are, and a bar
/// when a heading with links to it is deleted.
@MainActor
@Suite struct BrokenLinkTests {
    let suiteName = "MarkupTests-\(UUID().uuidString)"
    let folder: URL
    let project: ProjectWindowController
    let document: MarkdownDocument
    let settings: Settings

    static let this = "Intro [up](#here) and [there](part/other.md#theirs)\n# Mine {#mine}\n## Here {#here}\nEnd"

    init() throws {
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupBrokenLinkTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("part"), withIntermediateDirectories: true)
        try Data(Self.this.utf8).write(to: folder.appendingPathComponent("this.md"))
        try Data("{#id: theirs}\n# Theirs\nSee [back](../this.md#here), [also](#here) and [web](https://a.com#here)".utf8)
            .write(to: folder.appendingPathComponent("part/other.md"))
        project = ProjectWindowController(root: folder)
        document = try MarkdownDocument(contentsOf: folder.appendingPathComponent("this.md"), ofType: "net.daringfireball.markdown")
        document.undoManager?.groupsByEvent = false
        settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        document.editor.settings = settings
        project.show(document)
        editor.checkLinks()
    }

    private var editor: EditorViewController { document.editor }
    private var textView: EditorTextView { editor.textView }

    private func cleanUp() {
        settings.defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: folder)
    }

    private func step(_ action: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        action()
        document.undoManager?.endUndoGrouping()
        editor.checkLinks()
    }

    /// The range of the line holding `text`, with the newline before it.
    private func lineWithNewlineBefore(_ text: String) -> NSRange {
        let line = (textView.string as NSString).range(of: text)
        return NSRange(location: line.location - 1, length: line.length + 1)
    }

    private func delete(_ range: NSRange) {
        step { textView.insertText("", replacementRange: range) }
    }

    private var brokenTexts: [String] {
        editor.brokenLinks.map { (textView.string as NSString).substring(with: $0) }
    }

    private var bar: DeletedHeadingBar { editor.deletedHeadingBar }

    @Test func linksToHeadingsThatAreThereAreNotMarked() {
        defer { cleanUp() }
        #expect(editor.brokenLinks.isEmpty)
        #expect(bar.isHidden && editor.deletedHeadingBarHeight.constant == 0)
    }

    @Test func linksToMissingHeadingsAreMarkedWithoutChangingTheText() throws {
        defer { cleanUp() }
        editor.load(markdown: "[a](#nowhere) [b](#mine) [c](part/other.md#nowhere) [d](part/missing.md#theirs) "
            + "[e](part/other.md#theirs) [f](#theirs) [g](https://a.com#x) [h](other.md)\n# Mine {#mine}")
        editor.checkLinks()
        #expect(brokenTexts == ["a", "c", "d"])
        let layoutManager = try #require(textView.layoutManager)
        #expect(layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: 0, effectiveRange: nil) as? NSColor
            == InlineStyle.brokenLinkColor)
        #expect(layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: 2, effectiveRange: nil) == nil)
        #expect(editor.textView(textView, willDisplayToolTip: "#nowhere", forCharacterAt: 0) == "#nowhere\nNo heading has this ID.")
        #expect(editor.textView(textView, willDisplayToolTip: "#mine", forCharacterAt: 2) == "#mine")
        #expect(editor.markdown.hasPrefix("[a](#nowhere) [b](#mine)"))
    }

    @Test func idOnlyLinksToOtherFilesNeedTheSetting() {
        defer { cleanUp() }
        editor.load(markdown: "[a](#theirs)")
        editor.checkLinks()
        #expect(editor.brokenLinks.isEmpty)
        settings.crossFileLinks = .withPath
        editor.checkLinks()
        #expect(brokenTexts == ["a"])
    }

    @Test func deletingAHeadingWithLinksShowsTheBar() {
        defer { cleanUp() }
        delete(lineWithNewlineBefore("Here"))
        #expect(!bar.isHidden && editor.deletedHeadingBarHeight.constant == DeletedHeadingBar.height)
        #expect(bar.label.stringValue == "3 links go to “Here”, which was deleted.")
        #expect(bar.places == [
            HeadingLinkPlace(file: nil, number: 0, text: "up"),
            HeadingLinkPlace(file: folder.appendingPathComponent("part/other.md").standardizedFileURL, number: 0, text: "back"),
            HeadingLinkPlace(file: folder.appendingPathComponent("part/other.md").standardizedFileURL, number: 1, text: "also"),
        ])
        #expect(brokenTexts == ["up"])
    }

    @Test func deletingAHeadingsTextLeavesNoIDOrMarker() {
        defer { cleanUp() }
        let here = (textView.string as NSString).range(of: "Here")
        delete(here)
        #expect(editor.markdown == "Intro [up](#here) and [there](part/other.md#theirs)\n# Mine {#mine}\n\nEnd")
        #expect(bar.label.stringValue == "3 links go to “Here”, which was deleted.")
        #expect(brokenTexts == ["up"])
        // Typing a new heading there gives it the ID back.
        textView.setSelectedRange(NSRange(location: here.location, length: 0))
        step { textView.insertText("There", replacementRange: textView.selectedRange()) }
        #expect(editor.markdown.contains("\n## There {#here}\n"))
        #expect(bar.isHidden && editor.brokenLinks.isEmpty)
    }

    @Test func linksWithoutAPathOnlyCountInTheirFileUnlessIDOnly() {
        defer { cleanUp() }
        settings.crossFileLinks = .withPath
        delete(lineWithNewlineBefore("Here"))
        #expect(bar.label.stringValue == "2 links go to “Here”, which was deleted.")
    }

    @Test func undoPutsTheHeadingBackAndHidesTheBar() {
        defer { cleanUp() }
        delete(lineWithNewlineBefore("Here"))
        editor.undoHeadingDeletion(nil)
        editor.checkLinks()
        #expect(bar.isHidden && editor.brokenLinks.isEmpty)
        #expect(editor.markdown == Self.this)
    }

    @Test func theNextEditHidesTheBarButTheLinkStaysMarked() {
        defer { cleanUp() }
        delete(lineWithNewlineBefore("Here"))
        step { textView.insertText("!", replacementRange: NSRange(location: (textView.string as NSString).length, length: 0)) }
        #expect(bar.isHidden)
        #expect(brokenTexts == ["up"])
    }

    @Test func deletingAHeadingWithoutLinksShowsNothing() {
        defer { cleanUp() }
        delete(lineWithNewlineBefore("Mine"))
        #expect(bar.isHidden)
    }

    @Test func makingAHeadingAParagraphCountsAsDeletingIt() {
        defer { cleanUp() }
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).range(of: "Here").location, length: 0))
        step {
            editor.stylePopUp.selectItem(withTag: BlockStyle.paragraph.rawValue)
            editor.stylePopUp.sendAction(editor.stylePopUp.action, to: editor.stylePopUp.target)
        }
        #expect(!bar.isHidden)
        #expect(brokenTexts == ["up"])
    }

    @Test func cuttingAndPastingAHeadingKeepsItsID() {
        defer { cleanUp() }
        let heading = (textView.string as NSString).range(of: "Here\n")
        textView.setSelectedRange(heading)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MarkupTests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(textView.writeSelection(to: pasteboard, type: .string))
        delete(heading)
        #expect(!bar.isHidden)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        step { _ = textView.readSelection(from: pasteboard, type: .string) }
        #expect(bar.isHidden && editor.brokenLinks.isEmpty)
        #expect(editor.markdown.hasPrefix("## Here {#here}\nIntro"))
    }

    @Test func partOfAHeadingIsCopiedAsText() {
        defer { cleanUp() }
        let part = (textView.string as NSString).range(of: "Her")
        #expect(editor.plainText(for: part) == "Her")
    }

    @Test func aCopiedHeadingDoesNotTakeTheIDToo() {
        defer { cleanUp() }
        let heading = (textView.string as NSString).range(of: "Here\n")
        textView.setSelectedRange(heading)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MarkupTests-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(textView.writeSelection(to: pasteboard, type: .string))
        #expect(pasteboard.string(forType: .string) == "## Here {#here}\n")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        step { _ = textView.readSelection(from: pasteboard, type: .string) }
        #expect(editor.markdown == "## Here\n" + Self.this)
    }

    @Test func aHeadingPastedFromAnotherFileGetsANewID() {
        defer { cleanUp() }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        step { textView.insertText("## Copied {#theirs}\n", replacementRange: textView.selectedRange()) }
        #expect(editor.markdown.hasPrefix("## Copied\nIntro"))
        document.addMissingHeadingIDs(fileName: "this.md")
        #expect(editor.markdown.hasPrefix("{#id: this_2_Copied}\n## Copied\nIntro"))
    }

    @Test func anIDTypedAtTheEndOfAHeadingBecomesItsID() {
        defer { cleanUp() }
        let end = NSMaxRange((textView.string as NSString).range(of: "Mine"))
        for character in " {#top}" {
            textView.setSelectedRange(NSRange(location: textView.selectedRange().location == 0 ? end
                : textView.selectedRange().location, length: 0))
            step { textView.insertText(String(character), replacementRange: textView.selectedRange()) }
        }
        #expect(editor.markdown.contains("\n# Mine {#top}\n"))
        #expect(textView.string.contains("\nMine\n"))
    }

    @Test func showLinksSelectsALinkInThisFile() {
        defer { cleanUp() }
        editor.selectHeadingLink(number: 1)
        #expect((textView.string as NSString).substring(with: textView.selectedRange()) == "there")
    }

    @Test func theMarkdownViewMarksNothing() {
        defer { cleanUp() }
        delete(lineWithNewlineBefore("Here"))
        editor.setShowingMarkdown(true)
        editor.checkLinks()
        #expect(bar.isHidden && editor.brokenLinks.isEmpty)
        editor.setShowingMarkdown(false)
        editor.checkLinks()
        #expect(bar.isHidden && brokenTexts == ["up"])
    }
}
