import Testing
@testable import MarkupCore

@Suite struct MarkdownCodecTests {
    @Test func parsesHeadingLevels() {
        let lines = MarkdownCodec.lines(fromMarkdown: "# One\n## Two\n### Three\nBody")
        #expect(lines == [
            Line(style: .heading, text: "One"),
            Line(style: .subheading, text: "Two"),
            Line(style: .subsubheading, text: "Three"),
            Line(style: .paragraph, text: "Body"),
        ])
    }

    @Test(arguments: ["#hashtag", "#### Four", "  # Indented", "text # not at start"])
    func leavesNonHeadingsAsParagraphs(markdown: String) {
        #expect(MarkdownCodec.lines(fromMarkdown: markdown) == [Line(style: .paragraph, text: markdown)])
    }

    @Test func keepsExtraSpacesInHeadingText() {
        #expect(MarkdownCodec.lines(fromMarkdown: "#  Title") == [Line(style: .heading, text: " Title")])
    }

    @Test func emptyHeadingIsJustTheMarker() {
        #expect(MarkdownCodec.lines(fromMarkdown: "##") == [Line(style: .subheading, text: "")])
        #expect(MarkdownCodec.markdown(from: [Line(style: .subheading, text: "")]) == "##")
    }

    @Test func escapesParagraphsThatLookLikeHeadings() {
        #expect(MarkdownCodec.markdown(from: [Line(style: .paragraph, text: "# not a heading")]) == "\\# not a heading")
        #expect(MarkdownCodec.lines(fromMarkdown: "\\# not a heading") == [Line(style: .paragraph, text: "# not a heading")])
    }

    @Test func serializesHeadings() {
        let lines = [Line(style: .heading, text: "Title"), Line(style: .paragraph, text: "Body")]
        #expect(MarkdownCodec.markdown(from: lines) == "# Title\nBody")
    }

    private func item(_ text: String, level: Int = 0, _ marker: ListMarker = .bullet) -> Line {
        Line(style: .paragraph, text: text, list: ListItem(level: level, marker: marker))
    }

    @Test func parsesLists() {
        let lines = MarkdownCodec.lines(fromMarkdown: "- Milk\n  - Free range\n    - Organic\n- [ ] Call\n- [x] Paid")
        #expect(lines == [
            item("Milk"),
            item("Free range", level: 1),
            item("Organic", level: 2),
            item("Call", .unchecked),
            item("Paid", .checked),
        ])
    }

    @Test(arguments: ["-x", "-", "* star", "+ plus", "1. one", "   - odd indent", " - one space", "-\tTab"])
    func leavesOtherListSyntaxAsParagraphs(markdown: String) {
        #expect(MarkdownCodec.lines(fromMarkdown: markdown) == [Line(style: .paragraph, text: markdown)])
    }

    @Test func listItemTextIsNotParsedFurther() {
        #expect(MarkdownCodec.lines(fromMarkdown: "- # Not a heading") == [item("# Not a heading")])
        #expect(MarkdownCodec.lines(fromMarkdown: "- - Not nested") == [item("- Not nested")])
        #expect(MarkdownCodec.lines(fromMarkdown: "- [ ]") == [item("[ ]")])
        #expect(MarkdownCodec.lines(fromMarkdown: "- [X] Capital") == [item("[X] Capital")])
    }

    @Test func emptyItems() {
        #expect(MarkdownCodec.lines(fromMarkdown: "- ") == [item("")])
        #expect(MarkdownCodec.lines(fromMarkdown: "- [ ] ") == [item("", .unchecked)])
        #expect(MarkdownCodec.markdown(from: [item("", level: 1)]) == "  - ")
    }

    @Test func escapesTextThatLooksLikeAList() {
        #expect(MarkdownCodec.markdown(from: [Line(style: .paragraph, text: "- not a list")]) == "\\- not a list")
        #expect(MarkdownCodec.markdown(from: [Line(style: .paragraph, text: "  - not a list")]) == "  \\- not a list")
        #expect(MarkdownCodec.markdown(from: [item("[ ] not a task")]) == "- \\[ ] not a task")
        #expect(MarkdownCodec.lines(fromMarkdown: "  \\- not a list") == [Line(style: .paragraph, text: "  - not a list")])
        #expect(MarkdownCodec.lines(fromMarkdown: "- \\[ ] not a task") == [item("[ ] not a task")])
    }

    @Test func headingPrefix() {
        #expect(MarkdownCodec.headingPrefix(of: "# Title")! == (BlockStyle.heading, 2))
        #expect(MarkdownCodec.headingPrefix(of: "### ")! == (BlockStyle.subsubheading, 4))
        #expect(MarkdownCodec.headingPrefix(of: "#") == nil)
        #expect(MarkdownCodec.headingPrefix(of: "#Title") == nil)
        #expect(MarkdownCodec.headingPrefix(of: "#### Four") == nil)
        #expect(MarkdownCodec.headingPrefix(of: " # Indented") == nil)
    }

    @Test func listPrefix() {
        #expect(MarkdownCodec.listPrefix(of: "- a")! == (ListItem(level: 0, marker: .bullet), 2))
        #expect(MarkdownCodec.listPrefix(of: "  - [ ] a")! == (ListItem(level: 1, marker: .unchecked), 8))
        #expect(MarkdownCodec.listPrefix(of: "-a") == nil)
    }

    @Test(arguments: [
        "",
        "\n",
        "Body\n",
        "# Title\n\nSome *body* text.\n\n## Section\n### Sub\n",
        "\\# escaped\n\\\\# double escaped\n\\plain backslash",
        "#\n##\n###\n####",
        "> quote\n```\n# in a code block\n```",
        "- Milk\n  - Free range\n- [ ] Call\n- [x] Paid\n",
        "- \n- [ ] \n- [ ]\n-\n- - x\n- \\[ ] x\n- \\\\[x] y\n\\- p\n  \\- q\n   - r",
    ])
    func roundTrips(markdown: String) {
        #expect(MarkdownCodec.markdown(from: MarkdownCodec.lines(fromMarkdown: markdown)) == markdown)
    }

    @Test func readsCodeBlocks() {
        let lines = MarkdownCodec.lines(fromMarkdown: "Before\n```swift\nlet x = 1\n# not a heading\n```\nAfter")
        #expect(lines == [
            Line(style: .paragraph, text: "Before"),
            Line(style: .code, text: "let x = 1", fence: CodeFence(backticks: 3, info: "swift")),
            Line(style: .code, text: "# not a heading"),
            Line(style: .paragraph, text: "After"),
        ])
    }

    @Test func writesCodeBlocksBetweenFences() {
        #expect(MarkdownCodec.markdown(from: [
            Line(style: .code, text: "a"), Line(style: .code, text: "- b"), Line(style: .paragraph, text: "c"),
        ]) == "```\na\n- b\n```\nc")
        // A fence starts a new block, even straight after another.
        #expect(MarkdownCodec.markdown(from: [
            Line(style: .code, text: "a"), Line(style: .code, text: "b", fence: CodeFence(info: "sh")),
        ]) == "```\na\n```\n```sh\nb\n```")
    }

    @Test func lengthensTheFenceIfALineWouldCloseIt() {
        let markdown = MarkdownCodec.markdown(from: [Line(style: .code, text: "```"), Line(style: .code, text: "x")])
        #expect(markdown == "````\n```\nx\n````")
        #expect(MarkdownCodec.lines(fromMarkdown: markdown).map(\.text) == ["```", "x"])
    }

    @Test(arguments: [
        "```", "```\n```", "```\nno closing", "````\nx\n```", "```\na\n```\nb\n```",
        "```js\n\n  indented\n```", "\\```\nx\n```", "text ```\n```",
    ])
    func codeBlocksRoundTrip(markdown: String) {
        #expect(MarkdownCodec.markdown(from: MarkdownCodec.lines(fromMarkdown: markdown)) == markdown)
    }

    @Test func escapesParagraphsThatWouldOpenACodeBlock() {
        let lines = [Line(style: .paragraph, text: "```"), Line(style: .paragraph, text: "x"),
                     Line(style: .paragraph, text: "```")]
        let markdown = MarkdownCodec.markdown(from: lines)
        #expect(markdown == "\\```\nx\n```")
        #expect(MarkdownCodec.lines(fromMarkdown: markdown) == lines)
    }
}
