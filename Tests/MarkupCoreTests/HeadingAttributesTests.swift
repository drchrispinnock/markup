import MarkupCore
import Testing

/// A heading's other attributes, such as Leanpub's `sample: true`, which
/// share the ID's line, and making IDs ones Markua accepts.
@Suite struct HeadingAttributesTests {
    private func heading(_ markdown: String) -> Line? {
        MarkdownCodec.lines(fromMarkdown: markdown).first(where: \.isHeading)
    }

    private func rewritten(_ markdown: String) -> String {
        MarkdownCodec.markdown(from: MarkdownCodec.lines(fromMarkdown: markdown))
    }

    @Test func readsTheIDAndOtherAttributesFromOneLine() {
        let anchor = heading("{id: setup, sample: true}\n# Setting up")?.anchor
        #expect(anchor?.id == "setup" && anchor?.form == .idAttribute && anchor?.others == ["sample: true"])
        #expect(anchor?.isSample == true)
        #expect(heading("{#setup, sample: true}\n# A")?.anchor?.id == "setup")
        #expect(heading("{id: x}\n# A")?.anchor == HeadingAnchor(id: "x", form: .idAttribute, written: "{id: x}"))
        #expect(heading("{class: part, title: \"Part, One\"}\n# A")?.anchor?.others == ["class: part", "title: \"Part, One\""])
    }

    @Test func aLineOfOtherAttributesAloneIsTheHeadingsToo() {
        let lines = MarkdownCodec.lines(fromMarkdown: "{sample: true}\n# Chapter")
        #expect(lines.count == 1)
        #expect(lines[0].anchor?.hasID == false && lines[0].anchor?.isSample == true)
    }

    @Test(arguments: ["{sample: true}\n# A", "{id: x, sample: true}\n# A", "{sample: true, #x}\n## B",
                      "{ id: x ,sample:true }\n# C", "{class: part, sample: true}\n# Part", "{mainmatter}\n# A",
                      "{pagebreak}\n# A", "{Sample: true}\n# A", "\\{sample: true}\n# Escaped", "{sample: true}\nText",
                      "{sample: true}\n\n# Apart", "{#a}\n{#b}\n# Two IDs", "{#above}\n# Title {#end}"])
    func roundTrips(markdown: String) {
        #expect(rewritten(markdown) == markdown)
    }

    @Test func linesThatArentAttributesStayText() {
        for markdown in ["{mainmatter}\n# A", "{pagebreak}\n# A", "{Sample: true}\n# A", "{begin-hanging-paragraphs}\n# A",
                         "{sample: \"open}\n# A", "{sample: true,}\n# A"] {
            #expect(MarkdownCodec.lines(fromMarkdown: markdown).count == 2, "\(markdown)")
        }
    }

    @Test func twoLinesAboveAHeadingAreWrittenAsOne() {
        // Markua would see only the line directly above the heading.
        #expect(rewritten("{#id: x}\n{sample: true}\n# A\nText") == "{id: x, sample: true}\n# A\nText")
        #expect(rewritten("{sample: true}\n{#x}\n# A") == "{id: x, sample: true}\n# A")
        // An ID at the end of the heading, which Markua ignores, moves up.
        #expect(rewritten("{sample: true}\n# A {#x}") == "{id: x, sample: true}\n# A")
    }

    @Test func sampleCanBeSetAndTakenOff() {
        var anchor = HeadingAnchor(id: "x", form: .braceLine, written: "{#x}")
        anchor.isSample = true
        #expect(anchor.markdown == "{id: x, sample: true}")
        anchor.isSample = false
        #expect(anchor.markdown == "{#x}")
        var bare = HeadingAnchor(id: "", form: .idAttribute, others: ["sample: false"])
        bare.isSample = true
        #expect(bare.markdown == "{sample: true}")
        #expect(HeadingAnchor(id: "x", form: .idLine).markdown == "{#id: x}")
    }

    @Test func addingKeepsTheIDAndReplacesAttributesWithTheSameKey() {
        let anchor = HeadingAnchor(id: "x", form: .idAttribute, others: ["sample: false", "class: part"])
        let added = anchor.adding(HeadingAnchor(id: "", form: .idAttribute, others: ["sample: true"]))
        #expect(added.id == "x" && added.others == ["class: part", "sample: true"])
        #expect(anchor.adding(HeadingAnchor(id: "y", form: .braceLine)).id == "y")
    }

    @Test func migrationRenamesIDsMarkuaDoesntAcceptAndTheLinksToThem() {
        let renames = HeadingIDMigration.renames(for: ["170_dapps_1_Intro", "fine", "a.b", "IDa_b"])
        #expect(renames == ["170_dapps_1_Intro": "ID170_dapps_1_Intro", "a.b": "a_b"])
        let markdown = """
            {#id: 170_dapps_1_Intro}
            # Intro
            See [here](#170_dapps_1_Intro), [there](other.md#170_dapps_1_Intro "Title") and [web](https://x.com/#170_dapps_1_Intro).
            {#id: fine}
            ## Fine
            ```
            [code](#170_dapps_1_Intro)
            ```
            """
        #expect(HeadingIDMigration.migrating(markdown: markdown, renames: renames) == """
            {id: ID170_dapps_1_Intro}
            # Intro
            See [here](#ID170_dapps_1_Intro), [there](other.md#ID170_dapps_1_Intro "Title") and [web](https://x.com/#170_dapps_1_Intro).
            {id: fine}
            ## Fine
            ```
            [code](#170_dapps_1_Intro)
            ```
            """)
        #expect(HeadingIDMigration.migrating(markdown: "{#x}\n# A\n[a](#x)", renames: renames) == "{#x}\n# A\n[a](#x)")
        #expect(HeadingIDMigration.migrating(markdown: "{#id: 2}\n{sample: true}\n# A", renames: ["2": "ID2"])
            == "{id: ID2, sample: true}\n# A")
    }
}
