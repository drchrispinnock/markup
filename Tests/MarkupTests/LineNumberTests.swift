import AppKit
import Testing
@testable import Markup

/// View > Show Line Numbers: the Markdown view's line numbers.
@MainActor
@Suite struct LineNumberTests {
    let suiteName = "MarkupTests-\(UUID().uuidString)"
    let editor: EditorViewController

    init() {
        _ = NSApplication.shared
        editor = EditorViewController()
        editor.settings = Settings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    private var scrollView: NSScrollView { editor.textView.enclosingScrollView! }

    @Test func shownOnlyInTheMarkdownViewWhileOn() {
        defer { editor.settings.defaults.removePersistentDomain(forName: suiteName) }
        editor.load(markdown: "# Title\n\nText\n")
        #expect(!editor.settings.showsLineNumbers)
        #expect(!scrollView.rulersVisible)

        editor.toggleLineNumbers(nil)
        #expect(editor.settings.showsLineNumbers)
        #expect(!scrollView.rulersVisible)

        editor.setShowingMarkdown(true)
        #expect(scrollView.rulersVisible)
        #expect(scrollView.verticalRulerView is LineNumberRulerView)

        editor.toggleLineNumbers(nil)
        #expect(!scrollView.rulersVisible)
        editor.toggleLineNumbers(nil)
        editor.setShowingMarkdown(false)
        #expect(!scrollView.rulersVisible)
    }

    @Test func plainTextShowsThemToo() {
        let editor = EditorViewController(plainText: true)
        editor.settings = self.editor.settings
        defer { editor.settings.defaults.removePersistentDomain(forName: suiteName) }
        editor.settings.showsLineNumbers = true
        #expect(editor.textView.enclosingScrollView!.rulersVisible)
    }

    @Test func countsAnEmptyLastLine() {
        #expect(LineNumberRulerView.lineCount(of: "") == 1)
        #expect(LineNumberRulerView.lineCount(of: "a") == 1)
        #expect(LineNumberRulerView.lineCount(of: "a\nb\n") == 3)
    }
}

/// Edit > Go To Line, in both views.
@MainActor
@Suite struct GoToLineTests {
    let editor: EditorViewController
    static let markdown = "---\ntitle: A\n---\n# Title\n\n- item\n\n| a | b |\n| - | - |\n| c | d |\n\nEnd\n"

    init() {
        _ = NSApplication.shared
        editor = EditorViewController()
        editor.load(markdown: Self.markdown)
    }

    private var selected: String {
        (editor.storage.string as NSString).substring(with: editor.textView.selectedRange())
    }

    @Test func selectsTheLineInTheMarkdownView() {
        editor.setShowingMarkdown(true)
        #expect(editor.markdownLineCount == 13)
        editor.goToLine(2)
        #expect(selected == "title: A")
        editor.goToLine(10)
        #expect(selected == "| c   | d   |")
        editor.goToLine(99)
        #expect(editor.textView.selectedRange() == NSRange(location: editor.storage.length, length: 0))
    }

    @Test func selectsWhatShowsTheLineInTheFormattedView() {
        #expect(editor.markdownLineCount == 13)
        editor.goToLine(4)
        #expect(selected == "Title")
        editor.goToLine(6)
        #expect(selected == "item")
        editor.goToLine(9)
        #expect(selected == "a")
        editor.goToLine(10)
        #expect(selected == "c")
        editor.goToLine(12)
        #expect(selected == "End")
        // Front matter isn't shown, so its lines go to the start.
        editor.goToLine(2)
        #expect(editor.textView.selectedRange().location == 0)
    }

    @Test func popoverGoesToTheNumberTyped() {
        var chosen: [Int] = []
        let controller = GoToLineController(lineCount: 13) { chosen.append($0) }
        _ = controller.view
        controller.field.stringValue = "5"
        controller.go(nil)
        controller.field.stringValue = "50"
        controller.go(nil)
        controller.field.stringValue = "0"
        controller.go(nil)
        #expect(chosen == [5, 13])
    }
}
