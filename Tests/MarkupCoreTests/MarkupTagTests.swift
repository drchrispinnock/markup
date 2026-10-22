import Testing
@testable import MarkupCore

@Suite struct MarkupTagTests {
    @Test func readsTagsInText() {
        let text = "We have <!-- MARKUPTAG noofbakers-->2<!-- ENDMARKUPTAG --> bakers and <!--MARKUPTAG x -->??<!--ENDMARKUPTAG-->."
        let tags = MarkupTag.tags(in: text)
        #expect(tags.map(\.tag.name) == ["noofbakers", "x"])
        #expect(tags.map(\.tag.value) == ["2", "??"])
        #expect(tags[0].range == 8..<58)
        // Written back exactly as read.
        #expect(tags.map(\.tag.markdown) == ["<!-- MARKUPTAG noofbakers-->2<!-- ENDMARKUPTAG -->",
                                             "<!--MARKUPTAG x -->??<!--ENDMARKUPTAG-->"])
    }

    @Test func writesNewTagsInTheUsualForm() {
        #expect(MarkupTag(name: "noofbakers", value: "2").markdown == "<!-- MARKUPTAG noofbakers-->2<!-- ENDMARKUPTAG -->")
    }

    @Test(arguments: ["<!-- MARKUPTAG a-->1", "<!-- MARKUPTAG -->1<!-- ENDMARKUPTAG -->",
                      "<!-- MARKUPTAG a-->1\n<!-- ENDMARKUPTAG -->", "<!-- MARKUPTAG a b-->1<!-- ENDMARKUPTAG -->",
                      "<!-- MARKUPTAG a-->1<!-- other --><!-- ENDMARKUPTAG -->"])
    func otherTextIsNotATag(text: String) {
        #expect(MarkupTag.tags(in: text).isEmpty)
    }

    @Test func readsTheTagFile() {
        let file = "# Tags\n\nnoofbakers|2\n  name | Signet |extra\nempty|\nnopipe\nbad name|x\r\nlast|3"
        #expect(TagFile.values(from: file) == ["noofbakers": "2", "name": "Signet", "last": "3"])
    }

    @Test func updatesValuesOutsideCode() {
        let markdown = """
            # <!-- MARKUPTAG a-->old<!-- ENDMARKUPTAG -->
            Text <!-- MARKUPTAG a-->old<!-- ENDMARKUPTAG --> and <!-- MARKUPTAG gone-->1<!-- ENDMARKUPTAG -->
            ```
            <!-- MARKUPTAG a-->old<!-- ENDMARKUPTAG -->
            ```
            """
        #expect(MarkupTag.updating(markdown: markdown, from: TagSources(tags: ["a": "new"])) == """
            # <!-- MARKUPTAG a-->new<!-- ENDMARKUPTAG -->
            Text <!-- MARKUPTAG a-->new<!-- ENDMARKUPTAG --> and <!-- MARKUPTAG gone-->??<!-- ENDMARKUPTAG -->
            ```
            <!-- MARKUPTAG a-->old<!-- ENDMARKUPTAG -->
            ```
            """)
        let current = "x <!-- MARKUPTAG a-->new<!-- ENDMARKUPTAG -->\n"
        #expect(MarkupTag.updating(markdown: current, from: TagSources(tags: ["a": "new"])) == current)
    }

    @Test func inlineMarkdownKeepsATagWhole() {
        let text = "**<!-- MARKUPTAG a-->*2*<!-- ENDMARKUPTAG -->** left"
        let spans = InlineMarkdown.spans(in: text)
        #expect(spans.first?.text == "<!-- MARKUPTAG a-->*2*<!-- ENDMARKUPTAG -->")
        #expect(spans.first?.styles == [.bold])
        #expect(InlineMarkdown.markdown(for: spans) == text)
    }
}

@Suite struct BibliographyTests {
    static let file = """
        # Our sources
        SEC|Tezos
        R-1|Tezos — a self-amending crypto-ledger White paper, L. M. Goodman, 2014, https://tezos.com/whitepaper.pdf
        R-2|Tezos - Getting Started, https://tezos.com/learn/getting-started/

        R-3|Tezos, Wikipedia entry, https://en.wikipedia.org/wiki/Tezos
        SEC|Tezos Governance
        A-0|[Alternative Hangzhou proposal PsCUKj6wy](https://forum.tezosagora.org/t/hangzhou-pscukj6wy/3729)
        """

    @Test func numbersEntriesInOrderAcrossSections() {
        let bibliography = Bibliography(text: Self.file)
        #expect(bibliography.sections.map(\.title) == ["Tezos", "Tezos Governance"])
        #expect(bibliography.entries.map(\.key) == ["R-1", "R-2", "R-3", "A-0"])
        #expect(bibliography.citation(of: "A-0") == "[4]")
        #expect(bibliography.citation(of: "R-9") == "[??]")
        // Text after the first bar is kept whole.
        #expect(Bibliography(text: "X|a | b").entry(for: "X")?.text == "a | b")
    }

    @Test func entriesNeedNoKey() {
        let text = "SEC|Tezos\nTezos — a self-amending crypto-ledger, L. M. Goodman, 2014\nR-2|Getting Started\nSite, 2024 | online"
        let bibliography = Bibliography(text: text)
        let first = "Tezos — a self-amending crypto-ledger, L. M. Goodman, 2014"
        #expect(bibliography.entries.map(\.text) == [first, "Getting Started", "Site, 2024 | online"])
        // A key is made from the text: the same every time, and one a tag
        // name can be.
        let key = Bibliography.key(for: first)
        #expect(key.count == 8 && MarkupTag.isValid(name: key))
        #expect(bibliography.entries.map(\.key) == [key, "R-2", Bibliography.key(for: "Site, 2024 | online")])
        #expect(bibliography.citation(of: key) == "[1]")
        #expect(Bibliography(text: text).citation(of: key) == "[1]")
        #expect(bibliography.sections.map(\.title) == ["Tezos"])
    }

    @Test func writesTheBibliography() {
        #expect(Bibliography(text: Self.file).markdown(hanging: true) == """
            <!-- MARKUPBIBLIOGRAPHY -->
            {begin-hanging-paragraphs}

            **Tezos**

            [1] Tezos — a self-amending crypto-ledger White paper, L. M. Goodman, 2014, https://tezos.com/whitepaper.pdf

            [2] Tezos - Getting Started, https://tezos.com/learn/getting-started/

            [3] Tezos, Wikipedia entry, https://en.wikipedia.org/wiki/Tezos

            **Tezos Governance**

            [4] [Alternative Hangzhou proposal PsCUKj6wy](https://forum.tezosagora.org/t/hangzhou-pscukj6wy/3729)

            {end-hanging-paragraphs}
            <!-- ENDMARKUPBIBLIOGRAPHY -->
            """)
        #expect(Bibliography(text: "R|One").markdown(hanging: false)
            == "<!-- MARKUPBIBLIOGRAPHY -->\n[1] One\n<!-- ENDMARKUPBIBLIOGRAPHY -->")
    }

    @Test func readsCitations() {
        let tags = MarkupTag.tags(in: "See <!-- MARKUPBIBTAG R-1 -->[1]<!-- ENDMARKUPBIBTAG --> and <!-- MARKUPTAG a-->x<!-- ENDMARKUPTAG -->")
        #expect(tags.map(\.tag.kind) == [.citation, .tag])
        #expect(tags[0].tag == MarkupTag(name: "R-1", value: "[1]", kind: .citation))
        #expect(MarkupTag.citation("R-1").markdown == "<!-- MARKUPBIBTAG R-1 -->[??]<!-- ENDMARKUPBIBTAG -->")
        // The end must match the start.
        #expect(MarkupTag.tags(in: "<!-- MARKUPBIBTAG R-1 -->[1]<!-- ENDMARKUPTAG -->").isEmpty)
    }

    @Test func updatingSetsCitationsAndBibliographies() {
        let sources = TagSources(bibliography: Bibliography(text: "R-1|One\nR-2|Two"), hangingBibliography: false)
        let markdown = "Cite <!-- MARKUPBIBTAG R-2 -->[9]<!-- ENDMARKUPBIBTAG --> and <!-- MARKUPTAG a-->x<!-- ENDMARKUPTAG -->\n"
            + "<!-- MARKUPBIBLIOGRAPHY -->\nold\n<!-- ENDMARKUPBIBLIOGRAPHY -->\nAfter"
        let updated = MarkupTag.updating(markdown: markdown, from: sources)
        #expect(updated == "Cite <!-- MARKUPBIBTAG R-2 -->[2]<!-- ENDMARKUPBIBTAG --> and <!-- MARKUPTAG a-->x<!-- ENDMARKUPTAG -->\n"
            + "<!-- MARKUPBIBLIOGRAPHY -->\n[1] One\n\n[2] Two\n<!-- ENDMARKUPBIBLIOGRAPHY -->\nAfter")
        #expect(MarkupTag.updating(markdown: updated, from: sources) == updated)
    }
}
