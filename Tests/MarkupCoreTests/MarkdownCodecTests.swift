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

    @Test(arguments: ["-x", "-", "* star", "+ plus", "1.one", "1.", "a. letter", "i. roman", "1234567890. long",
                      "    - four spaces", "-\tTab"])
    func leavesOtherListSyntaxAsParagraphs(markdown: String) {
        #expect(MarkdownCodec.lines(fromMarkdown: markdown) == [Line(style: .paragraph, text: markdown)])
    }

    @Test func indentedUpToThreeSpacesIsAnItem() {
        #expect(MarkdownCodec.lines(fromMarkdown: " - one space") == [item("one space")])
        #expect(MarkdownCodec.lines(fromMarkdown: "   - three") == [item("three")])
    }

    private func numbered(_ text: String, _ number: Int, level: Int = 0) -> Line {
        Line(style: .paragraph, text: text, list: ListItem(level: level, marker: .numbered, number: number))
    }

    @Test func readsNumberedItemsNestedAsCommonMarkHasIt() {
        let lines = MarkdownCodec.lines(fromMarkdown: "1. One\n   1. Sub\n   2) Two\n      - Deeper\n2. Back\n  - Not nested in 2")
        #expect(lines == [
            numbered("One", 1), numbered("Sub", 1, level: 1), numbered("Two", 2, level: 1), item("Deeper", level: 2),
            numbered("Back", 2), item("Not nested in 2"),
        ])
        // Two spaces under a bullet nest; under "1. " they don't.
        #expect(MarkdownCodec.lines(fromMarkdown: "- a\n  1. b").map { $0.list?.level } == [0, 1])
        #expect(MarkdownCodec.lines(fromMarkdown: "10. a\n    b. x\n    1. c").map { $0.list?.level } == [0, nil, nil])
        #expect(MarkdownCodec.lines(fromMarkdown: "10. a\n    1. c").map { $0.list?.level } == [0, 1])
        // A blank line doesn't end a list; text does.
        #expect(MarkdownCodec.lines(fromMarkdown: "1. a\n\n   1. b\nText\n   1. c").map { $0.list?.level }
            == [0, nil, 1, nil, 0])
    }

    @Test func writesNewItemsIndentedToTheirParentsText() {
        let lines = [numbered("One", 1), numbered("Sub", 1, level: 1), item("Deeper", level: 2), numbered("Ten", 10),
                     numbered("Under ten", 1, level: 1), item("Bullet"), numbered("Under bullet", 1, level: 1)]
        let markdown = "1. One\n   1. Sub\n      - Deeper\n10. Ten\n    1. Under ten\n- Bullet\n  1. Under bullet"
        #expect(MarkdownCodec.markdown(from: lines) == markdown)
        #expect(MarkdownCodec.lines(fromMarkdown: markdown) == lines)
    }

    @Test func escapesTextThatLooksNumbered() {
        #expect(MarkdownCodec.markdown(from: [Line(style: .paragraph, text: "1. not a list")]) == "1\\. not a list")
        #expect(MarkdownCodec.lines(fromMarkdown: "1\\. not a list") == [Line(style: .paragraph, text: "1. not a list")])
        #expect(MarkdownCodec.markdown(from: [Line(style: .paragraph, text: "2024) a year")]) == "2024\\) a year")
        // Text indented too far to be an item isn't escaped.
        #expect(MarkdownCodec.markdown(from: [Line(style: .paragraph, text: "    1. code")]) == "    1. code")
        // Under an item, text indented to it would be a nested item.
        #expect(MarkdownCodec.markdown(from: [numbered("a", 1), Line(style: .paragraph, text: "   - b")])
            == "1. a\n   \\- b")
    }

    private func quote(_ text: String) -> Line {
        Line(style: .quote, text: text)
    }

    @Test func readsQuotes() {
        #expect(MarkdownCodec.lines(fromMarkdown: "> a\n>b\n>\n   > c\n>> d\n> # not a heading\n    > code") == [
            quote("a"), quote("b"), quote(""), quote("c"), quote("> d"), quote("# not a heading"),
            Line(style: .paragraph, text: "    > code"),
        ])
        // A quote ends a list.
        #expect(MarkdownCodec.lines(fromMarkdown: "1. a\n> q\n   1. b").map { $0.list?.level } == [0, nil, 0])
    }

    @Test func writesQuotes() {
        #expect(MarkdownCodec.markdown(from: [quote("a"), quote(""), quote("# b")]) == "> a\n>\n> # b")
        #expect(MarkdownCodec.markdown(from: [Line(style: .paragraph, text: "> not a quote")]) == "\\> not a quote")
        #expect(MarkdownCodec.lines(fromMarkdown: "\\> not a quote") == [Line(style: .paragraph, text: "> not a quote")])
        #expect(MarkdownCodec.markdown(from: [Line(style: .paragraph, text: "a > b")]) == "a > b")
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
        "1. a\n1. b\n   7) c\n  - d\n\n3. e\n1\\. f\n1\\\\. g\n\\1. h\n - i\n    - j",
        "> a\n>\n>b\n  > c\n>> d\n\\> e\n\\\\> f\n    > g\n- > h",
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

    @Test func keepsAMultiLineCommentWithItsFirstLine() {
        let markdown = "# Title\n<!-- note\n# not a heading\n- not a list\n-->\ntext\n<!-- never closed\n- item"
        let lines = MarkdownCodec.lines(fromMarkdown: markdown)
        #expect(lines.map(\.text) == ["Title", "<!-- note\n# not a heading\n- not a list\n-->", "text",
                                      "<!-- never closed", "item"])
        #expect(lines[1].style == .paragraph && lines[1].list == nil)
        #expect(MarkdownCodec.markdown(from: lines) == markdown)
    }

    @Test func escapesParagraphsThatWouldOpenACodeBlock() {
        let lines = [Line(style: .paragraph, text: "```"), Line(style: .paragraph, text: "x"),
                     Line(style: .paragraph, text: "```")]
        let markdown = MarkdownCodec.markdown(from: lines)
        #expect(markdown == "\\```\nx\n```")
        #expect(MarkdownCodec.lines(fromMarkdown: markdown) == lines)
    }
}
