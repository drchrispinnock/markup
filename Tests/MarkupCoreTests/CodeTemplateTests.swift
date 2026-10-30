import Testing
@testable import MarkupCore

/// Variables in code blocks, written as values after a template.
@Suite struct CodeTemplateTests {
    static func tag(_ name: String, _ value: String) -> String {
        MarkupTag(name: name, value: value).markdown
    }

    static let written = """
        Before
        <!-- MARKUPCODE
        Setting up octez-client (@octez@) ...
        mail me@@example.com --@> @a.b-c@@@
        -->
        ```sh
        Setting up octez-client (25.2) ...
        mail me@example.com --> 1@
        ```
        """

    @Test func readsATemplateAsVariablesInTheBlock() {
        let lines = MarkdownCodec.lines(fromMarkdown: Self.written)
        #expect(lines.map(\.style) == [.paragraph, .code, .code])
        #expect(lines[1].text == "Setting up octez-client (\(Self.tag("octez", "25.2"))) ...")
        #expect(lines[2].text == "mail me@example.com --> \(Self.tag("a.b-c", "1"))@")
        #expect(lines[1].fence == CodeFence(line: "```sh"))
        #expect(MarkdownCodec.markdown(from: lines) == Self.written)
    }

    @Test func writesVariablesInABlockAfterATemplate() {
        let lines = [Line(style: .code, text: "v\(Self.tag("v", "1")) and `@`"), Line(style: .code, text: "plain -->")]
        let markdown = MarkdownCodec.markdown(from: lines)
        #expect(markdown == "<!-- MARKUPCODE\nv@v@ and `@@`\nplain --@>\n-->\n```\nv1 and `@`\nplain -->\n```")
        #expect(MarkdownCodec.lines(fromMarkdown: markdown) == [Line(style: .code, text: lines[0].text, fence: CodeFence()),
                                                                lines[1]])
        // Without variables, no template.
        #expect(MarkdownCodec.markdown(from: [Line(style: .code, text: "x")]) == "```\nx\n```")
    }

    @Test func variablesWrittenInsideABlockMoveToATemplate() {
        let old = "```\n<!-- MARKUPTAG v-->1<!-- ENDMARKUPTAG -->\n```"
        #expect(MarkdownCodec.markdown(from: MarkdownCodec.lines(fromMarkdown: old))
            == "<!-- MARKUPCODE\n@v@\n-->\n```\n1\n```")
    }

    @Test func aBlockEditedElsewhereKeepsItsTextAndTheCommentStays() {
        let edited = "<!-- MARKUPCODE\nversion @v@\n-->\n```\nrelease 1\n```"
        let lines = MarkdownCodec.lines(fromMarkdown: edited)
        #expect(lines.map(\.style) == [.paragraph, .code])
        #expect(lines[1].text == "release 1")
        #expect(MarkdownCodec.markdown(from: lines) == edited)
        // A template not just before its block is only a comment.
        let apart = "<!-- MARKUPCODE\n@v@\n-->\n\n```\n1\n```"
        #expect(MarkdownCodec.lines(fromMarkdown: apart)[2].text == "1")
    }

    @Test func piecesReadTemplates() {
        let pieces = MarkdownCodec.pieces(of: "A\n<!-- MARKUPCODE\n@v@\n-->\n```\n1\n```\nB")
        #expect(pieces == [.text("A\n"), .code([Self.tag("v", "1")], fence: CodeFence()), .text("B")])
        // A comment's lines aren't a block.
        #expect(MarkdownCodec.pieces(of: "<!--\n```\nx\n```\n-->") == [.text("<!--\n```\nx\n```\n-->")])
    }

    @Test func updatingRewritesTheBlock() {
        let updated = MarkupTag.updating(markdown: Self.written, from: TagSources(variables: ["octez": "26.0", "a.b-c": "1"]))
        #expect(updated == Self.written.replacingOccurrences(of: "(25.2)", with: "(26.0)"))
    }
}
