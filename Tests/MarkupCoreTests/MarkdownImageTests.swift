import Testing
@testable import MarkupCore

@Suite struct MarkdownImageTests {
    private func images(_ text: String) -> [MarkdownImage] {
        MarkdownImage.images(in: text).map(\.image)
    }

    @Test func findsImagesAndTheirRanges() {
        let found = MarkdownImage.images(in: "See ![a cat](cats/tom.png) and ![](dog.jpg).")
        #expect(found.map(\.image) == [
            MarkdownImage(alt: "a cat", path: "cats/tom.png"),
            MarkdownImage(alt: "", path: "dog.jpg"),
        ])
        #expect(found.map(\.range) == [4..<26, 31..<43])
    }

    @Test func readsAngleBracketPathsAndIgnoresTitles() {
        #expect(images("![x](<my photos/a (1).png>)") == [MarkdownImage(alt: "x", path: "my photos/a (1).png")])
        #expect(images(#"![x](a.png "A title")"#) == [MarkdownImage(alt: "x", path: "a.png")])
    }

    @Test func unescapesAltText() {
        #expect(images(#"![\[1\] a\\b](a.png)"#) == [MarkdownImage(alt: #"[1] a\b"#, path: "a.png")])
    }

    @Test(arguments: [
        "![alt](a.png", "![alt] (a.png)", "[alt](a.png)", #"\![alt](a.png)"#, "![a\nb](a.png)", "![alt](a b.png)",
    ])
    func ignoresTextThatIsNotAnImage(text: String) {
        #expect(images(text).isEmpty)
    }

    @Test func rangesCountUTF16() {
        #expect(MarkdownImage.images(in: "😀 ![](a.png)").map(\.range) == [3..<13])
    }

    @Test func writesMarkdownThatReadsBack() {
        for image in [
            MarkdownImage(alt: "", path: "a.png"),
            MarkdownImage(alt: #"brackets [and] \ slash"#, path: "dir/sub dir/b (2).jpg"),
        ] {
            #expect(images(image.markdown) == [image])
        }
        #expect(MarkdownImage(alt: "A", path: "x/y.png").markdown == "![A](x/y.png)")
        #expect(MarkdownImage(alt: "", path: "my pic.png").markdown == "![](<my pic.png>)")
    }
}
