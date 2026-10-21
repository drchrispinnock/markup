import Testing
@testable import MarkupCore

@Suite struct HeadingAnchorTests {
    @Test func readsTheIDOnTheLineAbove() {
        #expect(MarkdownCodec.lines(fromMarkdown: "{#id: delegating}\n# Delegating and Staking\nText") == [
            Line(style: .heading, text: "Delegating and Staking",
                 anchor: HeadingAnchor(id: "delegating", form: .idLine, written: "{#id: delegating}")),
            Line(style: .paragraph, text: "Text"),
        ])
        #expect(MarkdownCodec.lines(fromMarkdown: "{#setup}\n## Setting up")[0].anchor
            == HeadingAnchor(id: "setup", form: .braceLine, written: "{#setup}"))
        #expect(MarkdownCodec.lines(fromMarkdown: "{#id:tight}\n#")[0]
            == Line(style: .heading, text: "", anchor: HeadingAnchor(id: "tight", form: .idLine, written: "{#id:tight}")))
    }

    @Test func readsTheIDAtTheEndOfTheHeading() {
        #expect(MarkdownCodec.lines(fromMarkdown: "### Setting up {#setup}") == [
            Line(style: .subsubheading, text: "Setting up", anchor: HeadingAnchor(id: "setup", form: .attribute, written: "{#setup}")),
        ])
        #expect(MarkdownCodec.lines(fromMarkdown: "## {#empty}")[0]
            == Line(style: .subheading, text: "", anchor: HeadingAnchor(id: "empty", form: .attribute, written: "{#empty}")))
    }

    @Test func anIDAtTheEndLeavesTheLineAboveAsText() {
        #expect(MarkdownCodec.lines(fromMarkdown: "{#above}\n# Title {#end}") == [
            Line(style: .paragraph, text: "{#above}"),
            Line(style: .heading, text: "Title", anchor: HeadingAnchor(id: "end", form: .attribute, written: "{#end}")),
        ])
    }

    @Test(arguments: ["{#x}\nText", "{#x}", "{#x}\n- item", "{#x}\n\n# Heading", "{# x}\n# Heading", "{#a b}\n# Heading",
                      "{#}\n# Heading", "{#id: a b}\n# Heading", " {#x}\n# Heading", "```\n{#x}\n# not a heading\n```"])
    func otherLinesAreNotIDs(markdown: String) {
        #expect(MarkdownCodec.lines(fromMarkdown: markdown).allSatisfy { $0.anchor == nil })
    }

    @Test(arguments: [
        "{#id: delegating}\n# Delegating", "{#id:x}\n# A", "{#id:   x  }\n## B", "{#x}\n### C", "# Title {#x}", "## {#x}",
        "{#a}\n{#b}\n# Two lines", "{#above}\n# Title {#end}", "\\{#x}\n# Escaped", "\\\\{#x}\n# Twice", "\\{#x}\nNot escaped",
        "# Ends with \\{#x}", "# Ends with \\\\{#x}", "# Ends {#a} {#b}", "{#x}", "Text {#x}", "{#x}\n\n# Apart",
    ])
    func roundTrips(markdown: String) {
        #expect(MarkdownCodec.markdown(from: MarkdownCodec.lines(fromMarkdown: markdown)) == markdown)
    }

    @Test func writesEachForm() {
        let heading = { (form: HeadingAnchor.Form) in
            MarkdownCodec.markdown(from: [Line(style: .subheading, text: "Setting up", anchor: HeadingAnchor(id: "setup", form: form))])
        }
        #expect(heading(.idLine) == "{#id: setup}\n## Setting up")
        #expect(heading(.braceLine) == "{#setup}\n## Setting up")
        #expect(heading(.attribute) == "## Setting up {#setup}")
    }

    @Test func aChangedIDIsWrittenAfresh() {
        var lines = MarkdownCodec.lines(fromMarkdown: "{#id:old}\n# Title")
        lines[0].anchor?.id = "new"
        #expect(MarkdownCodec.markdown(from: lines) == "{#id: new}\n# Title")
    }

    @Test func onlyHeadingsWriteTheirIDs() {
        let anchor = HeadingAnchor(id: "x", form: .idLine)
        #expect(MarkdownCodec.markdown(from: [Line(style: .paragraph, text: "Text", anchor: anchor)]) == "Text")
    }

    @Test func escapesTextThatWouldReadAsAnID() {
        let lines = [Line(style: .paragraph, text: "{#x}"), Line(style: .heading, text: "Title {#y}")]
        let markdown = MarkdownCodec.markdown(from: lines)
        #expect(markdown == "\\{#x}\n# Title \\{#y}")
        #expect(MarkdownCodec.lines(fromMarkdown: markdown) == lines)
    }

    @Test func makesIDsFromTheFileLevelAndFirstWord() {
        let scheme = HeadingIDScheme.fileLevelWord
        #expect(scheme.makeID(text: "Setting up my Dapp", level: 2, fileName: "170_dapps.md", taken: []) == "170_dapps_2_Setting")
        #expect(scheme.makeID(text: "**Delegating** and Staking", level: 1, fileName: "notes.md", taken: [])
            == "notes_1_Delegating")
        #expect(scheme.makeID(text: "Extraordinarily long", level: 1, fileName: "my notes.md", taken: [])
            == "my_notes_1_Extraordin")
        #expect(scheme.makeID(text: "", level: 3, fileName: nil, taken: []) == "Untitled_3")
        #expect(scheme.makeID(text: "Setting", level: 2, fileName: "a.md", taken: ["a_2_Setting", "a_2_Setting_2"])
            == "a_2_Setting_3")
    }

    @Test func makesHashIDs() {
        let id = HeadingIDScheme.hash.makeID(text: "Title", level: 1, fileName: "a.md", taken: [])
        #expect(id.count == 8 && id.allSatisfy(\.isHexDigit))
        #expect(HeadingIDScheme.hash.makeID(text: "Title", level: 1, fileName: "a.md", taken: []) == id)
        let other = HeadingIDScheme.hash.makeID(text: "Title", level: 1, fileName: "a.md", taken: [id])
        #expect(other != id && other.count == 8)
    }

    @Test func makesSlugs() {
        let scheme = HeadingIDScheme.slug
        #expect(scheme.makeID(text: "Setting up *my* Dapp!", level: 2, fileName: "a.md", taken: []) == "setting-up-my-dapp")
        #expect(scheme.makeID(text: "Intro", level: 1, fileName: nil, taken: ["intro", "intro-1"]) == "intro-2")
        #expect(scheme.makeID(text: "!!", level: 1, fileName: nil, taken: []) == "section")
    }
}
