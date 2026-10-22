import AppKit
import MarkupCore
import Testing
@testable import Markup

/// Tags: values from the project's tags.txt, shown as one character each.
@MainActor
@Suite struct TagTests {
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
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupTagTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# Tags\nnoofbakers|2\nname|Signet\n".utf8).write(to: folder.appendingPathComponent("tags.txt"))
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

    private func writeTags(_ text: String) throws {
        try Data(text.utf8).write(to: folder.appendingPathComponent("tags.txt"))
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

    @Test func aTagIsOneCharacterAndSavesAsWritten() {
        defer { cleanUp() }
        #expect(textView.string == "We have \u{FFFC} bakers.")
        #expect(tags == [MarkupTag(name: "noofbakers", value: "2")])
        #expect(editor.markdown == Self.this)
        #expect(textView.textStorage!.attribute(.toolTip, at: 8, effectiveRange: nil) as? String == "Tag noofbakers")
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

    @Test func valuesFollowTagsFileAsAnEditThatUndoes() throws {
        defer { cleanUp() }
        try writeTags("noofbakers|3\n")
        #expect(tags.map(\.value) == ["3"])
        #expect(editor.markdown == "We have \(Self.tag("noofbakers", "3")) bakers.")
        #expect(document.isDocumentEdited)
        document.undoManager?.undo()
        #expect(tags.map(\.value) == ["2"])

        try writeTags("other|1\n")
        #expect(tags.map(\.value) == [MarkupTag.unknownValue])
        #expect(textView.textStorage!.attribute(.toolTip, at: 8, effectiveRange: nil) as? String
            == "Tag noofbakers: tags.txt has no value for it")
    }

    @Test func unchangedValuesAreNotAnEdit() {
        defer { cleanUp() }
        editor.updateTags()
        #expect(!document.isDocumentEdited)
    }

    @Test func insertTagUsesTheValueOrQuestionMarks() {
        defer { cleanUp() }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        step { editor.insertTag(named: "name") }
        step { editor.insertTag(named: "missing") }
        #expect(tags.map(\.value) == ["Signet", "??", "2"])
        #expect(editor.markdown.hasPrefix(Self.tag("name", "Signet") + Self.tag("missing", "??") + "We have"))
        #expect(textView.selectedRange().location == 2)
        document.undoManager?.undo()
        #expect(tags.map(\.value) == ["Signet", "2"])
    }

    @Test func tagPopoverOffersTheTagsAndRefusesBadNames() {
        defer { cleanUp() }
        var inserted: [String] = []
        let controller = TagController(names: ["name", "noofbakers"]) { inserted.append($0) }
        _ = controller.view
        #expect(controller.comboBox.objectValues as? [String] == ["name", "noofbakers"])
        controller.comboBox.stringValue = "two words"
        controller.insert(nil)
        controller.comboBox.stringValue = " name "
        controller.insert(nil)
        #expect(inserted == ["name"])
        #expect(editor.makeTagController().view != nil)
    }

    @Test func pastedTagsBecomeTagsWithTheCurrentValue() {
        defer { cleanUp() }
        editor.load(markdown: "")
        step { textView.insertText("A " + Self.tag("name", "Stale") + " b", replacementRange: textView.selectedRange()) }
        #expect(textView.string == "A \u{FFFC} b")
        #expect(tags.map(\.value) == ["Signet"])
    }

    @Test func quickTagsNeedTheSetting() {
        defer { cleanUp() }
        editor.load(markdown: "")
        type("@name@ ")
        #expect(editor.markdown == "@name@ ")

        settings.quickTags = true
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

    @Test func tagsTakeInlineStylesAndCopyAsMarkdown() {
        defer { cleanUp() }
        editor.load(markdown: "**\(Self.tag("name", "Signet"))** text")
        #expect(textView.textStorage!.isBold(at: 0))
        #expect(editor.markdown == "**\(Self.tag("name", "Signet"))** text")
        #expect(editor.plainText(for: NSRange(location: 0, length: 1)) == "**\(Self.tag("name", "Signet"))**")
    }

    @Test func theMarkdownViewIsLeftAloneUntilSwitchingBack() throws {
        defer { cleanUp() }
        editor.setShowingMarkdown(true)
        try writeTags("noofbakers|5\n")
        #expect(textView.string == Self.this)
        // Switching clears the undo stack, open group and all, so group by
        // event as the app does.
        document.undoManager?.groupsByEvent = true
        editor.setShowingMarkdown(false)
        #expect(tags.map(\.value) == ["5"])
        #expect(document.undoManager?.canUndo == true)
    }

    @Test func updateTagsInProjectRewritesFilesOnDisk() throws {
        defer { cleanUp() }
        try writeTags("noofbakers|4\nname|New\n")
        document.undoManager?.undo()
        let values = try #require(project.tagValues())
        var result: (files: Int, failed: [URL]) = (0, [])
        step { result = project.updateTags(from: values) }
        let (files, failed) = result
        #expect(files == 2 && failed.isEmpty)
        #expect(tags.map(\.value) == ["4"])
        let other = try String(contentsOf: folder.appendingPathComponent("other.md"), encoding: .utf8)
        #expect(other == "By \(Self.tag("name", "New")).\n```\n\(Self.tag("name", "Old"))\n```\n")
        // The file on disk is read again.
        #expect(project.markdownFiles().first { $0.url.lastPathComponent == "other.md" }?.markdown == other)
    }

    @Test func updateTagsInProjectIsOnlyOfferedWithATagsFile() throws {
        defer { cleanUp() }
        let item = NSMenuItem(title: "", action: #selector(ProjectWindowController.updateTagsInProject(_:)), keyEquivalent: "")
        #expect(project.validateMenuItem(item))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("tags.txt"))
        project.filesChanged()
        #expect(!project.validateMenuItem(item))
        // Without a tags file, values are left as they are.
        editor.updateTags()
        #expect(tags.map(\.value) == ["2"])
    }

    @Test func aDocumentOutsideAProjectKeepsItsValues() {
        defer { cleanUp() }
        let alone = MarkdownDocument()
        alone.editor.load(markdown: "x " + Self.tag("name", "Kept"))
        alone.editor.updateTags()
        #expect(alone.editor.markdown == "x " + Self.tag("name", "Kept"))
    }
}
