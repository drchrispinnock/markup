import MarkupCore
import Testing
import UIKit
@testable import MarkupGo

/// Markdown read into the editor's text and written back unchanged,
/// including what the editor only shows as source.
@Suite struct RoundTripTests {
    @Test(arguments: [
        "",
        "Text",
        "Text\n",
        "# Title\n\nA *paragraph* with **bold**, ~~struck~~ and `code`.\n",
        "{id: ID1_intro}\n## Intro {#not-an-id}\n\nH~2~O and x^2^ and ==marked==.",
        "```swift\nlet x = 1\n\n```\nAfter\n```\nplain\n```",
        "- one\n- two\n  - nested\n\n1. first\n2) second\n\n> quoted *text*\n>\n> more",
        "---\ntitle: Hello\n---\n\n# Heading\n",
        "| a | b |\n|---|--:|\n| 1 | 2 |\n\nText after",
        "<!-- a comment\nover lines -->\nText [a link](https://example.com) and ![img](a.png)",
        "\\# not a heading\n\\- not a list\n\n{mainmatter}\n\n- [ ] task\n- [x] done",
        "Line with <!-- MARKUPTAG name-->value<!-- ENDMARKUPTAG --> in it",
    ])
    func roundTrip(_ markdown: String) {
        let text = FormattedText.attributedString(fromMarkdown: markdown)
        #expect(FormattedText.markdown(from: text) == markdown)
    }

    @Test func formatsOnlyParagraphsHeadingsAndCode() {
        let text = FormattedText.attributedString(fromMarkdown: "# Title\n- item\n**bold**")
        #expect(text.string == "Title\n- item\nbold")
        #expect(text.blockStyle(at: 0) == .heading1)
        #expect(text.sourceLine(at: 6) != nil)
        #expect(text.inlineStyles(at: 13) == [.bold])
    }

    @Test func editedSourceIsReadAgain() {
        let text = NSMutableAttributedString(attributedString: FormattedText.attributedString(fromMarkdown: "- one\nText"))
        text.replaceCharacters(in: NSRange(location: 2, length: 3), with: "uno")
        #expect(FormattedText.markdown(from: text) == "- uno\nText")
    }
}

/// The editor driven as typing would.
@MainActor @Suite struct EditorTests {
    let editor: EditorViewController
    let window: UIWindow

    init() {
        editor = EditorViewController(file: nil, markdown: "")
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = editor
        window.makeKeyAndVisible()
        editor.textView.becomeFirstResponder()
    }

    /// Types `text` as the keyboard does: asking the delegate first, which
    /// `insertText` alone doesn't.
    func type(_ text: String) {
        let textView = editor.textView
        for character in text.map(String.init)
        where editor.textView(textView, shouldChangeTextIn: textView.selectedRange, replacementText: character) {
            textView.insertText(character)
        }
    }

    func load(_ markdown: String, caret: Int) {
        editor.load(markdown: markdown)
        editor.textView.selectedRange = NSRange(location: caret, length: 0)
    }

    @Test func typingKeepsTheLineStyle() {
        load("# Title", caret: 5)
        type(" here")
        #expect(editor.markdown == "# Title here")
    }

    @Test func hashSpaceMakesAHeading() {
        type("## Plan")
        #expect(editor.markdown == "## Plan")
        #expect(editor.storage.string == "Plan")
    }

    @Test func returnAfterAHeadingStartsAParagraph() {
        load("# Title\nText", caret: 5)
        type("\nNext")
        #expect(editor.markdown == "# Title\nNext\nText")
        load("# Title", caret: 5)
        type("\nNext")
        #expect(editor.markdown == "# Title\nNext")
    }

    @Test func fenceStartsACodeBlockAndEmptyLineEndsIt() {
        type("```swift\nlet x = 1\n\nAfter")
        #expect(editor.markdown == "```swift\nlet x = 1\n```\nAfter\n")
    }

    @Test func codeLinesAreNotFormatted() {
        load("```\n**x**\n```", caret: 0)
        #expect(editor.storage.string == "**x**")
        editor.textView.selectedRange = NSRange(location: 0, length: 5)
        editor.toggle(.bold)
        #expect(editor.markdown == "```\n**x**\n```")
    }

    @Test func styleMenuChangesLinesAndUndoes() {
        load("One\nTwo", caret: 0)
        editor.textView.selectedRange = NSRange(location: 1, length: 4)
        editor.setStyle(.heading2)
        #expect(editor.markdown == "## One\n## Two")
        editor.textView.undoManager?.undo()
        #expect(editor.markdown == "One\nTwo")
        editor.setStyle(.code)
        #expect(editor.markdown == "```\nOne\nTwo\n```")
    }

    @Test func boldOnSelectionAndWhenTyping() {
        load("plain text", caret: 0)
        editor.textView.selectedRange = NSRange(location: 6, length: 4)
        editor.toggle(.bold)
        #expect(editor.markdown == "plain **text**")
        editor.textView.selectedRange = NSRange(location: 10, length: 0)
        editor.toggle(.bold)
        type(" more")
        #expect(editor.markdown == "plain **text** more")
    }

    @Test func splittingAHeadingKeepsItsIDOnTheFirstPart() {
        load("# One Two {#id}", caret: 4)
        type("\n")
        #expect(editor.markdown.components(separatedBy: "{#id}").count == 2)
        #expect(editor.markdown.hasPrefix("# One"))
        #expect(editor.markdown.hasSuffix("\n# Two"))
    }

    @Test func sourceLinesStayAsWritten() {
        load("Text\n- item\n> quote", caret: 0)
        editor.textView.selectedRange = NSRange(location: 7, length: 0)
        type("an ")
        #expect(editor.markdown == "Text\n- an item\n> quote")
    }
}
