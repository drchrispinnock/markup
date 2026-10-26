import Testing
@testable import MarkupCore

@Suite struct FrontMatterTests {
    static let jekyll = "---\nlayout: post\n# a YAML comment\ntitle: Stacey's\n---\n\n# Heading\nText"

    @Test func readsFrontMatterAsItsOwnLines() {
        let lines = MarkdownCodec.lines(fromMarkdown: Self.jekyll)
        #expect(lines.prefix(5).allSatisfy { $0.style == .frontMatter })
        #expect(lines.prefix(5).map(\.text) == ["---", "layout: post", "# a YAML comment", "title: Stacey's", "---"])
        #expect(Array(lines.dropFirst(5)) == [Line(style: .paragraph, text: ""), Line(style: .heading, text: "Heading"),
                                              Line(style: .paragraph, text: "Text")])
    }

    @Test(arguments: [jekyll, "---\na: 1\n...\nText", "---  \na: 1\n---\t", "---\n---\n", "---\n- x\n---\n- y"])
    func roundTrips(markdown: String) {
        #expect(MarkdownCodec.markdown(from: MarkdownCodec.lines(fromMarkdown: markdown)) == markdown)
    }

    @Test(arguments: ["---\n\na: 1\n---", "---\na: 1", "Text\n---\na: 1\n---", " ---\na: 1\n---", "----\na: 1\n----", "---"])
    func otherTextIsNotFrontMatter(markdown: String) {
        #expect(MarkdownCodec.frontMatter(in: markdown) == nil)
        #expect(!MarkdownCodec.lines(fromMarkdown: markdown).contains { $0.style == .frontMatter })
    }

    @Test func splitsOffTheFrontMatter() {
        let split = MarkdownCodec.frontMatter(in: "---\na: 1\n---\nText\n")
        #expect(split?.frontMatter == "---\na: 1\n---\n")
        #expect(split?.body == "Text\n")
        let alone = MarkdownCodec.frontMatter(in: "---\na: 1\n...")
        #expect(alone?.frontMatter == "---\na: 1\n...")
        #expect(alone?.body == "")
    }

    @Test func holdsNoHeadingsLinksOrValues() {
        let markdown = "---\n# x {#id}\nlink: [a](#b)\nv: <!-- MARKUPTAG a-->old<!-- ENDMARKUPTAG -->\n---\nText"
        #expect(MarkdownCodec.headingIDs(inMarkdown: markdown).isEmpty)
        #expect(HeadingReference.occurrences(inMarkdown: markdown).isEmpty)
        #expect(MarkupTag.updating(markdown: markdown, from: TagSources(variables: ["a": "new"])) == markdown)
    }
}
