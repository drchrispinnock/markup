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
        #expect(MarkupTag.updating(markdown: markdown, from: ["a": "new"]) == """
            # <!-- MARKUPTAG a-->new<!-- ENDMARKUPTAG -->
            Text <!-- MARKUPTAG a-->new<!-- ENDMARKUPTAG --> and <!-- MARKUPTAG gone-->??<!-- ENDMARKUPTAG -->
            ```
            <!-- MARKUPTAG a-->old<!-- ENDMARKUPTAG -->
            ```
            """)
        let current = "x <!-- MARKUPTAG a-->new<!-- ENDMARKUPTAG -->\n"
        #expect(MarkupTag.updating(markdown: current, from: ["a": "new"]) == current)
    }

    @Test func inlineMarkdownKeepsATagWhole() {
        let text = "**<!-- MARKUPTAG a-->*2*<!-- ENDMARKUPTAG -->** left"
        let spans = InlineMarkdown.spans(in: text)
        #expect(spans.first?.text == "<!-- MARKUPTAG a-->*2*<!-- ENDMARKUPTAG -->")
        #expect(spans.first?.styles == [.bold])
        #expect(InlineMarkdown.markdown(for: spans) == text)
    }
}
