import AppKit
import MarkupCore
import Testing
@testable import Markup

/// Leanpub's `{sample: true}` on a heading's ID line, and fixing IDs for
/// Leanpub.
@MainActor
@Suite struct SampleTests {
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

    private func cleanUp() {
        editor.settings.defaults.removePersistentDomain(forName: suiteName)
    }

    private func step(_ action: () -> Void) {
        document.undoManager?.beginUndoGrouping()
        action()
        document.undoManager?.endUndoGrouping()
    }

    private func sampleItem(at index: Int) -> NSMenuItem? {
        let menu = NSMenu()
        editor.addSampleItem(to: menu, at: index)
        return menu.items.first { $0.action == #selector(EditorViewController.toggleSample(_:)) }
    }

    @Test func attributesAreHiddenAndSavedAsWritten() {
        defer { cleanUp() }
        let markdown = "{id: one, sample: true}\n# One\nText\n{sample: true}\n## Two"
        editor.load(markdown: markdown)
        #expect(textView.string == "One\nText\nTwo")
        #expect(editor.markdown == markdown)
    }

    @Test func includeInSampleTogglesTheAttributeUndoably() {
        defer { cleanUp() }
        editor.load(markdown: "{#one}\n# One\nText")
        #expect(sampleItem(at: 5) == nil)
        let item = sampleItem(at: 1)!
        #expect(item.state == .off)
        step { editor.toggleSample(item) }
        #expect(editor.markdown == "{id: one, sample: true}\n# One\nText")
        #expect(sampleItem(at: 1)?.state == .on)
        #expect(document.undoManager?.undoActionName == "Include in Sample")
        document.undoManager?.undo()
        #expect(editor.markdown == "{#one}\n# One\nText")
        step { editor.toggleSample(item) }
        step { editor.toggleSample(sampleItem(at: 1)!) }
        #expect(editor.markdown == "{#one}\n# One\nText")
    }

    @Test func aHeadingWithoutAnIDGetsItOnTheSampleLine() {
        defer { cleanUp() }
        editor.load(markdown: "# One")
        step { editor.toggleSample(sampleItem(at: 0)!) }
        #expect(editor.markdown == "{sample: true}\n# One")
        editor.addMissingHeadingIDs(scheme: .slug, form: .idAttribute, fileName: "a.md", taken: [])
        #expect(editor.markdown == "{id: one, sample: true}\n# One")
    }

    @Test func typedOrPastedAboveAHeadingItBecomesItsAttributes() {
        defer { cleanUp() }
        for character in "{sample: true}\n# One" {
            if character == "\n" {
                step { textView.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
            } else {
                step { textView.insertText(String(character), replacementRange: textView.selectedRange()) }
            }
        }
        #expect(textView.string == "One")
        #expect(editor.markdown == "{sample: true}\n# One")

        editor.load(markdown: "")
        step { textView.insertText("{#one}\n{sample: true}\n# One", replacementRange: textView.selectedRange()) }
        #expect(textView.string == "One")
        #expect(editor.markdown == "{id: one, sample: true}\n# One")
    }

    @Test func fixingIDsRenamesThemAndTheirLinksInBothViews() {
        defer { cleanUp() }
        let markdown = "{#id: 1_intro}\n# Intro\nSee [it](#1_intro).\n{#id: ok}\n## OK"
        let fixed = "{id: ID1_intro}\n# Intro\nSee [it](#ID1_intro).\n{id: ok}\n## OK"
        editor.load(markdown: markdown)
        step { editor.fixHeadingIDs(nil) }
        #expect(editor.markdown == fixed)
        document.undoManager?.undo()
        #expect(editor.markdown == markdown)

        editor.setShowingMarkdown(true)
        step { editor.fixHeadingIDs(nil) }
        #expect(textView.string == fixed)
    }
}
