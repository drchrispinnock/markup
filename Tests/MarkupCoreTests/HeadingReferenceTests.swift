import Testing
@testable import MarkupCore

@Suite struct HeadingReferenceTests {
    @Test func readsLinksToHeadings() {
        #expect(HeadingReference(destination: "#setup") == HeadingReference(id: "setup"))
        #expect(HeadingReference(destination: "part/other.md#setup") == HeadingReference(path: "part/other.md", id: "setup"))
        #expect(HeadingReference(destination: "my%20notes.md#a") == HeadingReference(path: "my notes.md", id: "a"))
    }

    @Test(arguments: ["https://example.com#top", "mailto:a@b.com#x", "#", "other.md", "other.md#", "#a b", ""])
    func otherDestinationsAreNot(destination: String) {
        #expect(HeadingReference(destination: destination) == nil)
    }

    @Test func findsTheLinksToHeadingsInMarkdown() {
        let markdown = "Intro [a *b*](#x) and [c](o.md#y) and [web](https://a.com#z)\n```\n[d](#z)\n```\n- [e](#x)"
        #expect(HeadingReference.occurrences(inMarkdown: markdown) == [
            .init(reference: HeadingReference(id: "x"), text: "a b"),
            .init(reference: HeadingReference(path: "o.md", id: "y"), text: "c"),
            .init(reference: HeadingReference(id: "x"), text: "e"),
        ])
    }

    @Test func listsHeadingIDs() {
        #expect(MarkdownCodec.headingIDs(inMarkdown: "{#a}\n# A\n## B {#b}\n{#c}\nText\n# C") == ["a", "b"])
    }
}
