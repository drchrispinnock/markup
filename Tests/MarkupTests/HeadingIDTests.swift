import AppKit
import MarkupCore
import Testing
@testable import Markup

/// Heading IDs: hidden in the Formatted view, kept as written, and added
/// when saving.
@MainActor
@Suite struct HeadingIDTests {
    let suiteName = "MarkupTests-\(UUID().uuidString)"
    let document: MarkdownDocument
    let editor: EditorViewController

    init() {
        _ = NSApplication.shared
        document = MarkdownDocument()
        document.undoManager?.groupsByEvent = false
        document.makeWindowControllers()
        editor = document.editor
        editor.settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    private var textView: EditorTextView { editor.textView }
    private var storage: NSTextStorage { editor.storage }

    private func cleanUp() {
        editor.settings.defaults.removePersistentDomain(forName: suiteName)
    }

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

    private func addIDs(taken: Set<String> = [], fileName: String = "170_dapps.md") {
        editor.addMissingHeadingIDs(scheme: editor.settings.headingIDScheme, form: editor.settings.headingIDForm,
                                    fileName: fileName, taken: taken)
    }

    static let sample = "{#id: delegating}\n# Delegating and Staking\nText\n## Setting up {#setup}"

    @Test func idsAreHiddenInTheFormattedViewAndSavedAsWritten() {
        defer { cleanUp() }
        editor.load(markdown: Self.sample)
        #expect(textView.string == "Delegating and Staking\nText\nSetting up")
        #expect(editor.headingAnchor(in: editor.lineRange(at: 0))?.id == "delegating")
        #expect(editor.headingAnchor(in: editor.lineRange(at: 23)) == nil)
        #expect(editor.markdown == Self.sample)
    }

    @Test func theMarkdownViewShowsThemToEdit() {
        defer { cleanUp() }
        editor.load(markdown: Self.sample)
        editor.setShowingMarkdown(true)
        #expect(textView.string == Self.sample)
        textView.setSelectedRange(NSRange(location: 6, length: 10))
        step { textView.insertText("staking", replacementRange: textView.selectedRange()) }
        editor.setShowingMarkdown(false)
        #expect(editor.headingAnchor(in: editor.lineRange(at: 0))?.id == "staking")
        #expect(editor.markdown.hasPrefix("{#id: staking}\n# Delegating"))
    }

    @Test func typingInAHeadingKeepsItsID() {
        defer { cleanUp() }
        editor.load(markdown: Self.sample)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        type("On ")
        textView.setSelectedRange(NSRange(location: 25, length: 0))
        type("!")
        #expect(editor.markdown.hasPrefix("{#id: delegating}\n# On Delegating and Staking!\nText"))
    }

    @Test func splittingAHeadingLeavesTheIDOnTheFirstPart() {
        defer { cleanUp() }
        editor.load(markdown: Self.sample)
        textView.setSelectedRange(NSRange(location: 10, length: 0))
        type("\n")
        #expect(editor.markdown.hasPrefix("{#id: delegating}\n# Delegating\n#  and Staking\nText"))
    }

    @Test func returnAtTheStartOfAHeadingKeepsTheIDOnItsText() {
        defer { cleanUp() }
        editor.load(markdown: Self.sample)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        type("\n")
        #expect(editor.markdown.hasPrefix("#\n{#id: delegating}\n# Delegating and Staking\nText"))
    }

    @Test func anIDTypedAboveAHeadingBecomesItsID() {
        defer { cleanUp() }
        type("{#id: mine}\n# Title")
        #expect(textView.string == "Title")
        #expect(editor.markdown == "{#id: mine}\n# Title")
    }

    @Test func pastedIDsBecomeTheHeadingsIDs() {
        defer { cleanUp() }
        step { textView.insertText("Intro\n{#first}\n# One\n{#id: second}\n## Two\n", replacementRange: textView.selectedRange()) }
        #expect(textView.string == "Intro\nOne\nTwo\n")
        #expect(editor.markdown == "Intro\n{#first}\n# One\n{#id: second}\n## Two\n")
    }

    @Test func savingAddsMissingIDsAndKeepsTheOthers() {
        defer { cleanUp() }
        editor.load(markdown: "# Setting up my Dapp\nText\n## Other {#x}\n### Setting again")
        addIDs(taken: ["170_dapps_1_Setting"])
        #expect(editor.markdown
            == "{#id: 170_dapps_1_Setting_2}\n# Setting up my Dapp\nText\n## Other {#x}\n{#id: 170_dapps_3_Setting}\n### Setting again")
        #expect(textView.string == "Setting up my Dapp\nText\nOther\nSetting again")
        addIDs(taken: ["170_dapps_1_Setting"])
        #expect(editor.markdown.hasPrefix("{#id: 170_dapps_1_Setting_2}\n#"))
    }

    @Test func newIDsFollowTheSettings() {
        defer { cleanUp() }
        editor.settings.headingIDForm = .attribute
        editor.settings.headingIDScheme = .slug
        editor.load(markdown: "# Setting up\n## Setting up")
        addIDs()
        #expect(editor.markdown == "# Setting up {#setting-up}\n## Setting up {#setting-up-1}")
    }

    @Test func savingInTheMarkdownViewInsertsTheIDsUndoably() {
        defer { cleanUp() }
        editor.setShowingMarkdown(true)
        step { textView.insertText("Intro\n# Title\n```\n# code\n```", replacementRange: textView.selectedRange()) }
        step { addIDs() }
        #expect(textView.string == "Intro\n{#id: 170_dapps_1_Title}\n# Title\n```\n# code\n```")
        document.undoManager?.undo()
        #expect(textView.string == "Intro\n# Title\n```\n# code\n```")
    }

    @Test func documentAddsIDsUnlessTurnedOff() {
        defer { cleanUp() }
        editor.load(markdown: "# Title")
        editor.settings.addsHeadingIDs = false
        document.addMissingHeadingIDs(fileName: "notes.md")
        #expect(editor.markdown == "# Title")
        editor.settings.addsHeadingIDs = true
        document.addMissingHeadingIDs(fileName: "notes.md")
        #expect(editor.markdown == "{#id: notes_1_Title}\n# Title")
    }

    @Test func settingsDefaultToIDLinesFromTheFileLevelAndWord() {
        defer { cleanUp() }
        let settings = editor.settings
        #expect(settings.addsHeadingIDs && settings.headingIDForm == .idLine && settings.headingIDScheme == .fileLevelWord)
        settings.headingIDForm = .braceLine
        settings.headingIDScheme = .hash
        settings.addsHeadingIDs = false
        let reread = Settings(defaults: settings.defaults)
        #expect(!reread.addsHeadingIDs && reread.headingIDForm == .braceLine && reread.headingIDScheme == .hash)
    }

    @Test func settingsWindowChangesThem() {
        defer { cleanUp() }
        let window = SettingsWindowController(settings: editor.settings)
        #expect(window.headingIDFormPopUp.numberOfItems == 3 && window.headingIDFormPopUp.indexOfSelectedItem == 0)
        window.headingIDSchemePopUp.selectItem(at: 2)
        window.headingIDsChanged(nil)
        #expect(editor.settings.headingIDScheme == .slug)
        window.addsHeadingIDsCheckbox.state = .off
        window.headingIDsChanged(nil)
        #expect(!editor.settings.addsHeadingIDs)
        window.crossFileLinksPopUp.selectItem(at: 1)
        window.headingIDsChanged(nil)
        #expect(editor.settings.crossFileLinks == .withPath)
    }
}

/// IDs are unique across a project's files.
@MainActor
@Suite struct ProjectHeadingIDTests {
    @Test func newIDsAreUniqueAcrossTheProject() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupIDTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("{#id: two_1_Intro}\n# Intro".utf8).write(to: folder.appendingPathComponent("sub/one.md"))
        try Data("# Intro\n## Intro {#two_2_Intro}".utf8).write(to: folder.appendingPathComponent("two.md"))
        let project = ProjectWindowController(root: folder)
        let document = try MarkdownDocument(contentsOf: folder.appendingPathComponent("two.md"),
                                            ofType: "net.daringfireball.markdown")
        let suiteName = "MarkupTests-\(UUID().uuidString)"
        document.editor.settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        defer { document.editor.settings.defaults.removePersistentDomain(forName: suiteName) }
        project.show(document)
        #expect(project.markdownFiles().map(\.url.lastPathComponent) == ["sub/one.md", "two.md"].map { ($0 as NSString).lastPathComponent })
        document.addMissingHeadingIDs(fileName: "two.md")
        #expect(document.editor.markdown == "{#id: two_1_Intro_2}\n# Intro\n## Intro {#two_2_Intro}")
    }
}

/// Cross links: links to a heading's ID, in this file or another.
@MainActor
@Suite struct CrossLinkTests {
    let suiteName = "MarkupTests-\(UUID().uuidString)"
    let folder: URL
    let project: ProjectWindowController
    let document: MarkdownDocument
    let settings: Settings

    init() throws {
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("MarkupLinkTests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("part"), withIntermediateDirectories: true)
        try Data("Intro\n# Mine\nText\n## Here {#here}".utf8).write(to: folder.appendingPathComponent("this.md"))
        try Data("{#id: theirs}\n# Theirs\n## *Setting* up".utf8).write(to: folder.appendingPathComponent("part/other.md"))
        project = ProjectWindowController(root: folder)
        document = try MarkdownDocument(contentsOf: folder.appendingPathComponent("this.md"), ofType: "net.daringfireball.markdown")
        document.undoManager?.groupsByEvent = false
        settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
        document.editor.settings = settings
        project.show(document)
    }

    private var editor: EditorViewController { document.editor }

    private func cleanUp() {
        settings.defaults.removePersistentDomain(forName: suiteName)
        for other in project.documents where other !== document {
            NSDocumentController.shared.removeDocument(other)
        }
        try? FileManager.default.removeItem(at: folder)
    }

    private func link(to title: String, selecting range: NSRange) {
        editor.textView.setSelectedRange(range)
        let target = editor.crossLinkTargets().first { $0.title == title }!
        document.undoManager?.beginUndoGrouping()
        editor.link(to: target)
        document.undoManager?.endUndoGrouping()
    }

    @Test func crossLinkButtonIsNextToTheLinkButton() {
        defer { cleanUp() }
        #expect(editor.crossLinkButton.superview === editor.headerView)
        #expect(editor.crossLinkButton.action == #selector(EditorViewController.insertCrossLink(_:)))
        let item = NSMenuItem(title: "Cross Link…", action: #selector(EditorViewController.insertCrossLink(_:)), keyEquivalent: "")
        #expect(editor.validateMenuItem(item))
        editor.setShowingMarkdown(true)
        #expect(!editor.crossLinkButton.isEnabled && !editor.validateMenuItem(item))
    }

    @Test func offersThisFilesHeadingsThenTheProjects() {
        defer { cleanUp() }
        let targets = editor.crossLinkTargets()
        #expect(targets.map(\.title) == ["Mine", "Here", "Theirs", "Setting up"])
        #expect(targets.map(\.level) == [1, 2, 1, 2])
        #expect(targets[2].file?.lastPathComponent == "other.md" && targets[3].index == 1)
        let controller = CrossLinkController(targets: targets) { _ in }
        controller.loadView()
        #expect(controller.popUp.itemTitles == ["This File", "Mine", "Here", "", "other.md", "Theirs", "Setting up"])
        #expect(controller.selectedTarget == targets[0])
        #expect(controller.popUp.menu?.items[2].indentationLevel == 2)
        settings.crossFileLinks = .off
        #expect(editor.crossLinkTargets().map(\.title) == ["Mine", "Here"])
        let alone = CrossLinkController(targets: editor.crossLinkTargets()) { _ in }
        alone.loadView()
        #expect(alone.popUp.itemTitles == ["Mine", "Here"])
    }

    @Test func linksTheSelectionToAHeadingInThisFile() {
        defer { cleanUp() }
        link(to: "Here", selecting: NSRange(location: 0, length: 5))
        #expect(editor.markdown.hasPrefix("[Intro](#here)\n"))
    }

    @Test func givesAHeadingWithoutAnIDOne() {
        defer { cleanUp() }
        settings.addsHeadingIDs = false
        link(to: "Mine", selecting: NSRange(location: 0, length: 5))
        #expect(editor.markdown == "[Intro](#this_1_Mine)\n{#id: this_1_Mine}\n# Mine\nText\n## Here {#here}")
    }

    @Test func withNoSelectionInsertsTheHeadingsTitle() {
        defer { cleanUp() }
        link(to: "Theirs", selecting: NSRange(location: 5, length: 0))
        #expect(editor.markdown.hasPrefix("Intro[Theirs](#theirs)\n"))
    }

    @Test func linksToOtherFilesWithTheirPathIfSet() {
        defer { cleanUp() }
        settings.crossFileLinks = .withPath
        link(to: "Theirs", selecting: NSRange(location: 0, length: 5))
        #expect(editor.markdown.hasPrefix("[Intro](part/other.md#theirs)\n"))
        #expect(project.documents.count == 2 && !project.documents[1].isDocumentEdited)
    }

    @Test func aHeadingInAnotherFileGetsAnIDThere() {
        defer { cleanUp() }
        link(to: "Setting up", selecting: NSRange(location: 0, length: 5))
        #expect(editor.markdown.hasPrefix("[Intro](#other_2_Setting)\n"))
        let other = project.documents.first { $0 !== document }!
        #expect(other.isDocumentEdited)
        #expect(other.currentMarkdown == "{#id: theirs}\n# Theirs\n{#id: other_2_Setting}\n## *Setting* up")
        #expect(project.currentDocument === document)
    }

    @Test func relativePaths() {
        defer { cleanUp() }
        let root = URL(fileURLWithPath: "/book")
        #expect(EditorViewController.relativePath(to: root.appendingPathComponent("a/b.md"), from: root) == "a/b.md")
        #expect(EditorViewController.relativePath(to: root.appendingPathComponent("b.md"), from: root.appendingPathComponent("a"))
            == "../b.md")
        #expect(EditorViewController.relativePath(to: root.appendingPathComponent("my file.md"), from: root) == "my%20file.md")
    }
}
