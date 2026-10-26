import Testing
@testable import MarkupCore

@Suite struct HTMLTagTests {
    @Test func readsLineBreaksImagesAndParagraphs() {
        let text = "a<br>b<BR/>c<br />d<p>e</p><P class=\"x\">"
        let tags = HTMLTag.tags(in: text)
        #expect(tags.map(\.tag.kind) == [.lineBreak, .lineBreak, .lineBreak, .paragraphStart, .paragraphEnd, .paragraphStart])
        #expect(tags.map(\.range) == [1..<5, 6..<11, 12..<18, 19..<22, 23..<27, 27..<40])
    }

    @Test func readsAnImagesAttributes() {
        let text = #"<img src="/assets/a b.jpeg" style="float:right; margin:20px;" ALT='Pie &amp; mash' width=300 hidden>"#
        let tag = HTMLTag.tags(in: text).first?.tag
        #expect(tag?.kind == .image)
        #expect(tag?.attributes == ["src": "/assets/a b.jpeg", "style": "float:right; margin:20px;", "alt": "Pie & mash",
                                    "width": "300", "hidden": ""])
        #expect(tag?.image == MarkdownImage(alt: "Pie & mash", path: "/assets/a b.jpeg"))
        #expect(HTMLTag.tags(in: text).first?.range == 0..<text.utf16.count)
    }

    @Test(arguments: ["<strong/>", "<big>", "</img>", "</b class=\"x\">", "<h7>", "\\<br>", "</br>", "</p class=\"x\">", "<pre>", "<brx>", "<img>", "<img alt=\"x\">", "<br", "< br>",
                      "<img src=\"a>"])
    func otherTextIsNotATag(text: String) {
        #expect(HTMLTag.tags(in: text).isEmpty)
    }

    @Test func readsAnImageWrittenEitherWay() {
        #expect(MarkdownImage.image(written: "![a](b.png)") == MarkdownImage(alt: "a", path: "b.png"))
        #expect(MarkdownImage.image(written: "<img src=b.png>") == MarkdownImage(alt: "", path: "b.png"))
        #expect(MarkdownImage.image(written: "<br>") == nil)
    }

    @Test func attributesAreNotEmphasisAndAreWrittenBackUnescaped() {
        let text = #"<img src="a*b*.png" alt="~x~"> and *y*"#
        let spans = InlineMarkdown.spans(in: text)
        #expect(spans.map(\.text) == [#"<img src="a*b*.png" alt="~x~"> and "#, "y"])
        #expect(InlineMarkdown.markdown(for: spans) == text)
    }

    @Test func readsFormattingTags() {
        let tags = HTMLTag.tags(in: "<STRONG>a</strong><b>b</b><em>c</em><i>d</i><h4 id=\"x\">e</h4><h1>")
        #expect(tags.map(\.tag.kind) == [.formatStart(.bold), .formatEnd(.bold), .formatStart(.bold), .formatEnd(.bold),
                                         .formatStart(.italic), .formatEnd(.italic), .formatStart(.italic), .formatEnd(.italic),
                                         .formatStart(.heading(4)), .formatEnd(.heading(4)), .formatStart(.heading(1))])
    }

    @Test func formatsRunFromEachOpeningTagToItsClosingOne() {
        // "<b>ab<i>c</i></b>d<i>e" with the tags as one character each:
        // b, a, b, i, c, /i, /b, d, i, e.
        let tags: [(range: Range<Int>, tag: HTMLTag)] = [
            (0..<1, HTMLTag(kind: .formatStart(.bold))), (3..<4, HTMLTag(kind: .formatStart(.italic))),
            (5..<6, HTMLTag(kind: .formatEnd(.italic))), (6..<7, HTMLTag(kind: .formatEnd(.bold))),
            (8..<9, HTMLTag(kind: .formatStart(.italic))),
        ]
        let ranges = HTMLFormat.ranges(in: 10, tags: tags)
        #expect(ranges.map(\.range) == [1..<3, 4..<5])
        #expect(ranges.map(\.formats) == [[.bold], [.bold, .italic]])
        // A closing tag with no opening one does nothing.
        #expect(HTMLFormat.ranges(in: 3, tags: [(1..<2, HTMLTag(kind: .formatEnd(.bold)))]).isEmpty)
    }
}
