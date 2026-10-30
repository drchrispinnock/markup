import AppKit
import MarkupCore
import Testing
@testable import Markup

/// Leanpub's {mainmatter} and {backmatter} lines.
@MainActor
@Suite struct LeanpubDivisionTests {
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

    private func menuItem(_ division: LeanpubDivision) -> NSMenuItem {
        let item = NSMenuItem(title: division.title, action: #selector(EditorViewController.insertLeanpubDivision(_:)),
                              keyEquivalent: "")
        item.tag = LeanpubDivision.allCases.firstIndex(of: division)!
        return item
    }

    private func isDivision(at index: Int) -> Bool {
        (textView.textStorage!.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment)?.attachmentCell
            is DivisionAttachmentCell
    }

    @Test func aDivisionIsOneCharacterAndSavesAsWritten() {
        // Markua no longer has {frontmatter}.
        let markdown = "{frontmatter}\nPreface\n{mainmatter}\n# One\n{backmatter}\nNot {mainmatter}"
        editor.load(markdown: markdown)
        #expect(textView.string == "{frontmatter}\nPreface\n\u{FFFC}\nOne\n\u{FFFC}\nNot {mainmatter}")
        #expect(isDivision(at: 22) && isDivision(at: 28))
        #expect(editor.markdown == markdown)
        #expect(editor.plainText(for: NSRange(location: 22, length: 2)) == "{mainmatter}\n")
    }

    @Test func insertPutsItAtTheCaretOnALineOfItsOwn() {
        editor.load(markdown: "Preface\n# One")
        // At the start of a line, above it.
        textView.setSelectedRange(NSRange(location: 8, length: 0))
        step { editor.insertLeanpubDivision(menuItem(.mainmatter)) }
        #expect(editor.markdown == "Preface\n{mainmatter}\n# One")
        #expect(textView.selectedRange().location == 10)
        #expect(document.undoManager?.undoActionName == "Insert Main Matter")
        document.undoManager?.undo()
        #expect(editor.markdown == "Preface\n# One")

        // In the middle, splitting the line.
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        step { editor.insertLeanpubDivision(menuItem(.mainmatter)) }
        #expect(editor.markdown == "Pre\n{mainmatter}\nface\n# One")
        #expect(textView.selectedRange().location == 6)
        document.undoManager?.undo()

        // At the end of a line, below it, and on an empty line, there.
        textView.setSelectedRange(NSRange(location: 11, length: 0))
        step { editor.insertLeanpubDivision(menuItem(.backmatter)) }
        #expect(editor.markdown == "Preface\n# One\n{backmatter}")
        step { textView.insertNewline(nil) }
        step { editor.insertLeanpubDivision(menuItem(.mainmatter)) }
        #expect(editor.markdown == "Preface\n# One\n{backmatter}\n{mainmatter}")
    }

    @Test func typedItBecomesTheDivision() {
        editor.load(markdown: "")
        type("{backmatter}")
        #expect(textView.string == "\u{FFFC}")
        #expect(editor.markdown == "{backmatter}")
        type("\nAppendix")
        #expect(editor.markdown == "{backmatter}\nAppendix")
    }
}
