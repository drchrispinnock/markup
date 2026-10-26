import AppKit
import MarkupCore
import Testing
@testable import Markup

/// Variables: values from the project's variables.txt (or tags.txt), shown
/// as one character each.
@MainActor
@Suite struct VariableTests {
    let suiteName = "MarkupTests-\(UUID().uuidString)"
    let folder: URL
    let project: ProjectWindowController
    let document: MarkdownDocument
    let settings: Settings

    static func tag(_ name: String, _ value: String) -> String {
        "<!-- MARKUPTAG \(name)-->\(value)<!-- ENDMARKUPTAG -->"
    }

    static let this = "We have \(tag("noofbakers", "2")) bakers."

    init() throws {
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupVariableTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# Variables\nnoofbakers|2\nname|Signet\n".utf8).write(to: folder.appendingPathComponent("variables.txt"))
        try Data(Self.this.utf8).write(to: folder.appendingPathComponent("this.md"))
        try Data("By \(Self.tag("name", "Old")).\n```\n\(Self.tag("name", "Old"))\n```\n".utf8)
            .write(to: folder.appendingPathComponent("other.md"))
        project = ProjectWindowController(root: folder)
        document = try MarkdownDocument(contentsOf: folder.appendingPathComponent("this.md"), ofType: "net.daringfireball.markdown")
        document.undoManager?.groupsByEvent = false
        settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        document.editor.settings = settings
        project.show(document)
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
    }

    private func type(_ text: String) {
        for character in text {
            step { textView.insertText(String(character), replacementRange: textView.selectedRange()) }
        }
    }

    private func writeVariables(_ text: String, to file: String = "variables.txt") throws {
        try Data(text.utf8).write(to: folder.appendingPathComponent(file))
        step { project.filesChanged() }
    }

    /// The tags in the text, in order.
    private var tags: [MarkupTag] {
        var tags: [MarkupTag] = []
        textView.textStorage!.enumerateAttribute(.markupTag, in: NSRange(location: 0, length: textView.string.utf16.count)) {
            value, run, _ in
            if let tag = value as? MarkupTag { tags += Array(repeating: tag, count: run.length) }
        }
        return tags
    }

    @Test func aVariableIsOneCharacterAndSavesAsWritten() {
        defer { cleanUp() }
        #expect(textView.string == "We have \u{FFFC} bakers.")
        #expect(tags == [MarkupTag(name: "noofbakers", value: "2")])
        #expect(editor.markdown == Self.this)
        #expect(textView.textStorage!.attribute(.toolTip, at: 8, effectiveRange: nil) as? String == "Variable noofbakers")
    }

    @Test func showsTheValueInTheLinesFont() throws {
        defer { cleanUp() }
        editor.load(markdown: "# \(Self.tag("name", "Signet"))")
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        let cell = try #require((textView.textStorage!.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?
            .attachmentCell as? TagAttachmentCell)
        let frame = cell.cellFrame(for: textView.textContainer!, proposedLineFragment: .zero, glyphPosition: .zero,
                                   characterIndex: 0)
        let width = NSAttributedString(string: "Signet", attributes: [.font: BlockStyle.heading.font(for: [])]).size().width
        #expect(abs(frame.width - (ceil(width) + 6)) < 1)
    }

    @Test func valuesFollowVariablesFileAsAnEditThatUndoes() throws {
        defer { cleanUp() }
        try writeVariables("noofbakers|3\n")
        #expect(tags.map(\.value) == ["3"])
        #expect(editor.markdown == "We have \(Self.tag("noofbakers", "3")) bakers.")
        #expect(document.isDocumentEdited)
        document.undoManager?.undo()
        #expect(tags.map(\.value) == ["2"])

        try writeVariables("other|1\n")
        #expect(tags.map(\.value) == [MarkupTag.unknownValue])
        #expect(textView.textStorage!.attribute(.toolTip, at: 8, effectiveRange: nil) as? String
            == "Variable noofbakers has no value")
    }

    @Test func unchangedValuesAreNotAnEdit() {
        defer { cleanUp() }
        editor.updateTags()
        #expect(!document.isDocumentEdited)
    }

    @Test func insertTagUsesTheValueOrQuestionMarks() {
        defer { cleanUp() }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        step { editor.insertVariable(named: "name") }
        step { editor.insertVariable(named: "missing") }
        #expect(tags.map(\.value) == ["Signet", "??", "2"])
        #expect(editor.markdown.hasPrefix(Self.tag("name", "Signet") + Self.tag("missing", "??") + "We have"))
        #expect(textView.selectedRange().location == 2)
        document.undoManager?.undo()
        #expect(tags.map(\.value) == ["Signet", "2"])
    }

    @Test func variablePopoverOffersTheVariablesAndRefusesBadNames() {
        defer { cleanUp() }
        var inserted: [String] = []
        let controller = VariableController(names: ["name", "noofbakers"]) { inserted.append($0) }
        _ = controller.view
        #expect(controller.comboBox.objectValues as? [String] == ["name", "noofbakers"])
        controller.comboBox.stringValue = "two words"
        controller.insert(nil)
        controller.comboBox.stringValue = " name "
        controller.insert(nil)
        #expect(inserted == ["name"])
        _ = editor.makeVariableController().view
    }

    @Test func pastedVariablesBecomeVariablesWithTheCurrentValue() {
        defer { cleanUp() }
        editor.load(markdown: "")
        step { textView.insertText("A " + Self.tag("name", "Stale") + " b", replacementRange: textView.selectedRange()) }
        #expect(textView.string == "A \u{FFFC} b")
        #expect(tags.map(\.value) == ["Signet"])
    }

    @Test func quickVariablesNeedTheSetting() {
        defer { cleanUp() }
        editor.load(markdown: "")
        type("@name@ ")
        #expect(editor.markdown == "@name@ ")

        settings.quickVariables = true
        editor.load(markdown: "")
        type("By @name@")
        #expect(tags.map(\.name) == ["name"])
        // Undo takes back the conversion and the @ that made it, as with
        // the other shortcuts.
        document.undoManager?.undo()
        #expect(editor.markdown == "By @name")
        editor.load(markdown: "")
        type("By @name@ and a@b.com or me@x@ ")
        #expect(editor.markdown == "By \(Self.tag("name", "Signet")) and a@b.com or me@x@ ")
    }

    @Test func variablesTakeInlineStylesAndCopyAsMarkdown() {
        defer { cleanUp() }
        editor.load(markdown: "**\(Self.tag("name", "Signet"))** text")
        #expect(textView.textStorage!.isBold(at: 0))
        #expect(editor.markdown == "**\(Self.tag("name", "Signet"))** text")
        #expect(editor.plainText(for: NSRange(location: 0, length: 1)) == "**\(Self.tag("name", "Signet"))**")
    }

    @Test func theMarkdownViewIsLeftAloneUntilSwitchingBack() throws {
        defer { cleanUp() }
        editor.setShowingMarkdown(true)
        try writeVariables("noofbakers|5\n")
        #expect(textView.string == Self.this)
        // Switching clears the undo stack, open group and all, so group by
        // event as the app does.
        document.undoManager?.groupsByEvent = true
        editor.setShowingMarkdown(false)
        #expect(tags.map(\.value) == ["5"])
        #expect(document.undoManager?.canUndo == true)
    }

    @Test func updateVariablesInProjectRewritesFilesOnDisk() throws {
        defer { cleanUp() }
        try writeVariables("noofbakers|4\nname|New\n")
        document.undoManager?.undo()
        let sources = project.tagSources(settings: settings)
        var result: (files: Int, failed: [URL]) = (0, [])
        step { result = project.updateTags(from: sources) }
        let (files, failed) = result
        #expect(files == 2 && failed.isEmpty)
        #expect(tags.map(\.value) == ["4"])
        let other = try String(contentsOf: folder.appendingPathComponent("other.md"), encoding: .utf8)
        #expect(other == "By \(Self.tag("name", "New")).\n```\n\(Self.tag("name", "Old"))\n```\n")
        // The file on disk is read again.
        #expect(project.markdownFiles().first { $0.url.lastPathComponent == "other.md" }?.markdown == other)
    }

    @Test func updateVariablesInProjectIsOnlyOfferedWithAVariablesFile() throws {
        defer { cleanUp() }
        let item = NSMenuItem(title: "", action: #selector(ProjectWindowController.updateVariablesInProject(_:)), keyEquivalent: "")
        #expect(project.validateMenuItem(item))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("variables.txt"))
        project.filesChanged()
        #expect(!project.validateMenuItem(item))
        // Without a variables file, values are left as they are.
        editor.updateTags()
        #expect(tags.map(\.value) == ["2"])
    }

    @Test func tagsFileIsReadToo() throws {
        defer { cleanUp() }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("variables.txt"))
        try writeVariables("noofbakers|6\nname|Old\n", to: "tags.txt")
        #expect(tags.map(\.value) == ["6"])
        // variables.txt's values come first.
        try writeVariables("noofbakers|7\n")
        #expect(tags.map(\.value) == ["7"])
        #expect(project.variableValues() == ["noofbakers": "7", "name": "Old"])
    }

    @Test func aDocumentOutsideAProjectKeepsItsValues() {
        defer { cleanUp() }
        let alone = MarkdownDocument()
        alone.editor.load(markdown: "x " + Self.tag("name", "Kept"))
        alone.editor.updateTags()
        #expect(alone.editor.markdown == "x " + Self.tag("name", "Kept"))
    }
}

/// Citations and bibliographies from the project's bibliography.txt.
@MainActor
@Suite struct BibliographyEditorTests {
    let suiteName = "MarkupTests-\(UUID().uuidString)"
    let folder: URL
    let project: ProjectWindowController
    let document: MarkdownDocument
    let settings: Settings

    static func cite(_ key: String, _ value: String) -> String {
        "<!-- MARKUPBIBTAG \(key) -->\(value)<!-- ENDMARKUPBIBTAG -->"
    }

    static let file = "SEC|Tezos\nR-1|The *white* paper, https://tezos.com/whitepaper.pdf\nR-2|[Getting started](https://tezos.com/learn)\n"

    init() throws {
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupBibTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(Self.file.utf8).write(to: folder.appendingPathComponent("bibliography.txt"))
        try Data("See \(Self.cite("R-2", "[2]")).\n# Further reading\nEnd".utf8).write(to: folder.appendingPathComponent("this.md"))
        project = ProjectWindowController(root: folder)
        document = try MarkdownDocument(contentsOf: folder.appendingPathComponent("this.md"), ofType: "net.daringfireball.markdown")
        document.undoManager?.groupsByEvent = false
        settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        document.editor.settings = settings
        project.show(document)
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
    }

    private func writeBibliography(_ text: String) throws {
        try Data(text.utf8).write(to: folder.appendingPathComponent("bibliography.txt"))
        step { project.filesChanged() }
    }

    /// The lines of the Markdown from the start of the bibliography.
    private var bibliographyMarkdown: String {
        let markdown = editor.markdown
        return String(markdown[markdown.range(of: "<!-- MARKUPBIBLIOGRAPHY -->")!.lowerBound...])
    }

    private func insertBibliographyAfterHeading() {
        let heading = (textView.string as NSString).range(of: "Further reading")
        textView.setSelectedRange(NSRange(location: NSMaxRange(heading), length: 0))
        step { editor.insertBibliography(nil) }
    }

    @Test func citeInsertsTheEntrysNumber() {
        defer { cleanUp() }
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        step { editor.insertCitation(of: "R-1") }
        #expect(editor.markdown.hasPrefix("See" + Self.cite("R-1", "[1]") + " " + Self.cite("R-2", "[2]")))
        step { editor.insertCitation(of: "nope") }
        #expect(editor.markdown.contains(Self.cite("nope", "[??]")))
    }

    @Test func citationPopoverListsEntriesBySection() {
        defer { cleanUp() }
        var cited: [String] = []
        let controller = CitationController(bibliography: Bibliography(text: Self.file)) { cited.append($0) }
        _ = controller.view
        #expect(controller.popUp.itemTitles == ["Tezos", "[1] The white paper, https://tezos.com/whitepaper.pdf",
                                                "[2] Getting started"])
        #expect(controller.selectedEntry?.key == "R-1")
        controller.popUp.selectItem(at: 2)
        controller.cite(nil)
        #expect(cited == ["R-2"])
        let none = CitationController(bibliography: nil) { _ in }
        _ = none.view
        #expect(!none.citeButton.isEnabled)
    }

    @Test func insertsTheBibliographyAndKeepsItUpToDate() throws {
        defer { cleanUp() }
        insertBibliographyAfterHeading()
        let expected = """
            <!-- MARKUPBIBLIOGRAPHY -->
            {begin-hanging-paragraphs}

            **Tezos**

            [1] The *white* paper, https://tezos.com/whitepaper.pdf

            [2] [Getting started](https://tezos.com/learn)

            {end-hanging-paragraphs}
            <!-- ENDMARKUPBIBLIOGRAPHY -->
            End
            """
        #expect(bibliographyMarkdown == expected)
        // The markers and Leanpub's lines take no space.
        let marker = NSMaxRange((textView.string as NSString).range(of: "Further reading")) + 1
        #expect(textView.string.utf16.dropFirst(marker).prefix(5).elementsEqual("\u{FFFC}\n\u{FFFC}\n\n".utf16))
        for index in [marker, marker + 2] {
            #expect(textView.textStorage!.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
                == HTMLComment.hiddenLineStyle)
        }
        // Nothing to change.
        step { #expect(!editor.updateTags(from: project.tagSources(settings: settings))) }

        try writeBibliography("R-0|First\n" + Self.file)
        #expect(editor.markdown.hasPrefix("See \(Self.cite("R-2", "[3]"))."))
        #expect(bibliographyMarkdown.contains("[1] First\n\n**Tezos**\n\n[2] The *white* paper"))
        #expect(bibliographyMarkdown.hasSuffix("<!-- ENDMARKUPBIBLIOGRAPHY -->\nEnd"))
        document.undoManager?.undo()
        #expect(bibliographyMarkdown == expected)
        #expect(editor.markdown.hasPrefix("See \(Self.cite("R-2", "[2]"))."))
    }

    @Test func withoutHangingParagraphs() {
        defer { cleanUp() }
        settings.hangingBibliography = false
        insertBibliographyAfterHeading()
        #expect(bibliographyMarkdown.hasPrefix("<!-- MARKUPBIBLIOGRAPHY -->\n**Tezos**\n\n[1]"))
    }

    @Test func updateVariablesInProjectRewritesBibliographiesOnDisk() throws {
        defer { cleanUp() }
        let other = folder.appendingPathComponent("other.md")
        try Data("x \(Self.cite("R-1", "[7]"))\n<!-- MARKUPBIBLIOGRAPHY -->\n<!-- ENDMARKUPBIBLIOGRAPHY -->\n".utf8).write(to: other)
        project.filesChanged()
        settings.hangingBibliography = false
        var result: (files: Int, failed: [URL]) = (0, [])
        step { result = project.updateTags(from: project.tagSources(settings: settings)) }
        #expect(result.files == 1)
        #expect(try String(contentsOf: other, encoding: .utf8) == "x \(Self.cite("R-1", "[1]"))\n<!-- MARKUPBIBLIOGRAPHY -->\n"
            + "**Tezos**\n\n[1] The *white* paper, https://tezos.com/whitepaper.pdf\n\n[2] [Getting started](https://tezos.com/learn)\n"
            + "<!-- ENDMARKUPBIBLIOGRAPHY -->\n")
    }

    @Test func bibliographyNeedsTheFile() throws {
        defer { cleanUp() }
        let item = NSMenuItem(title: "", action: #selector(EditorViewController.insertBibliography(_:)), keyEquivalent: "")
        #expect(editor.validateMenuItem(item))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("bibliography.txt"))
        project.filesChanged()
        #expect(!editor.validateMenuItem(item))
    }
}
