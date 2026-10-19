import Testing
@testable import MarkupCore

@Suite struct InlineMarkdownTests {
    @Test func readsBoldItalicAndBoth() {
        #expect(InlineMarkdown.spans(in: "a **b** *c* ***d*** e") == [
            InlineSpan("a "), InlineSpan("b", bold: true), InlineSpan(" "), InlineSpan("c", italic: true),
            InlineSpan(" "), InlineSpan("d", bold: true, italic: true), InlineSpan(" e"),
        ])
    }

    @Test func readsNestedEmphasis() {
        #expect(InlineMarkdown.spans(in: "**a *b* c**") == [
            InlineSpan("a ", bold: true), InlineSpan("b", bold: true, italic: true), InlineSpan(" c", bold: true),
        ])
        #expect(InlineMarkdown.spans(in: "*a **b***") == [
            InlineSpan("a ", italic: true), InlineSpan("b", bold: true, italic: true),
        ])
    }

    @Test(arguments: ["a * b", "2 * 3 * 4", "*", "**", "* a*", "*a *", "no stars", "**unclosed"])
    func leavesUnmatchedAsterisksAsText(text: String) {
        #expect(InlineMarkdown.spans(in: text) == [InlineSpan(text)])
    }

    @Test func readsStrikethrough() {
        #expect(InlineMarkdown.spans(in: "a ~~gone~~ b ~~**both**~~") == [
            InlineSpan("a "), InlineSpan("gone", strikethrough: true), InlineSpan(" b "),
            InlineSpan("both", bold: true, strikethrough: true),
        ])
    }

    @Test(arguments: ["~~one~", "~one~~", "~~~~four~~~~", "a ~~ b", "~~open", "x~y"])
    func leavesOtherTildesAsText(text: String) {
        #expect(InlineMarkdown.spans(in: text) == [InlineSpan(text)])
    }

    @Test func writesStrikethrough() {
        #expect(InlineMarkdown.markdown(for: [InlineSpan("a "), InlineSpan("gone", strikethrough: true)]) == "a ~~gone~~")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("~~not~~")]) == #"\~\~not\~\~"#)
        #expect(InlineMarkdown.markdown(for: [InlineSpan("a ~ b")]) == "a ~ b")
    }

    @Test func readsCodeSpansLiterally() {
        #expect(InlineMarkdown.spans(in: "run `ls *.md` now") == [
            InlineSpan("run "), InlineSpan("ls *.md", code: true), InlineSpan(" now"),
        ])
        #expect(InlineMarkdown.spans(in: "``a ` b``") == [InlineSpan("a ` b", code: true)])
        #expect(InlineMarkdown.spans(in: "` `` `") == [InlineSpan("``", code: true)])
        #expect(InlineMarkdown.spans(in: #"`a\*b`"#) == [InlineSpan(#"a\*b"#, code: true)])
        #expect(InlineMarkdown.spans(in: "**`x`**") == [InlineSpan("x", bold: true, code: true)])
        #expect(InlineMarkdown.spans(in: "`![a](b.png)`") == [InlineSpan("![a](b.png)", code: true)])
    }

    @Test(arguments: ["a ` b", "``x`", #"\`x`"#])
    func leavesUnmatchedBackticksAsText(text: String) {
        #expect(InlineMarkdown.spans(in: text).allSatisfy { !$0.code })
    }

    @Test func reportsWhereCodeDelimitersAre() {
        #expect(InlineMarkdown.emphases(in: "a `b` ` c `") == [
            .init(opening: 2..<3, closing: 4..<5, style: .code),
            .init(opening: 6..<8, closing: 9..<11, style: .code),
        ])
    }

    @Test func writesCodeSpans() {
        #expect(InlineMarkdown.markdown(for: [InlineSpan("run "), InlineSpan("ls *.md", code: true)]) == "run `ls *.md`")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("a`b", code: true)]) == "``a`b``")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("`x", code: true)]) == "`` `x ``")
        #expect(InlineMarkdown.markdown(for: [InlineSpan(" x ", code: true)]) == "`  x  `")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("x", bold: true, code: true), InlineSpan(" y", bold: true)])
            == "**`x` y**")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("`not code`")]) == #"\`not code\`"#)
    }

    @Test func readsEscapedAsterisks() {
        #expect(InlineMarkdown.spans(in: #"\*not italic\*"#) == [InlineSpan("*not italic*")])
    }

    @Test func keepsImagesWhole() {
        #expect(InlineMarkdown.spans(in: "**![a*b*](x*y*.png)**") == [InlineSpan("![a*b*](x*y*.png)", bold: true)])
    }

    @Test func reportsWhereTheAsterisksAre() {
        #expect(InlineMarkdown.emphases(in: "a **b** *c*") == [
            .init(opening: 2..<4, closing: 5..<7, style: .bold),
            .init(opening: 8..<9, closing: 10..<11, style: .italic),
        ])
        #expect(InlineMarkdown.emphases(in: "~~s~~") == [.init(opening: 0..<2, closing: 3..<5, style: .strikethrough)])
    }

    @Test func writesEmphasis() {
        #expect(InlineMarkdown.markdown(for: [
            InlineSpan("a "), InlineSpan("b", bold: true), InlineSpan(" "), InlineSpan("c", italic: true),
            InlineSpan("d", bold: true, italic: true),
        ]) == "a **b** *c**d***")
    }

    @Test func writesSpacesOutsideTheAsterisks() {
        #expect(InlineMarkdown.markdown(for: [InlineSpan("a"), InlineSpan(" bold ", bold: true), InlineSpan("b")])
            == "a **bold** b")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("   ", italic: true)]) == "   ")
    }

    @Test func escapesAsterisksOnlyWhenNeeded() {
        #expect(InlineMarkdown.markdown(for: [InlineSpan("2 * 3")]) == "2 * 3")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("*not italic*")]) == #"\*not italic\*"#)
        #expect(InlineMarkdown.markdown(for: [InlineSpan("*", bold: true)]) == #"**\***"#)
    }

    @Test(arguments: [
        "plain", "a **b** c", "*i* and **b** and ***bi***", "**a *b* c**", "*a **b** c*", "2 * 3", #"\*x\*"#,
        "**b***i*", "*i***b**", "x **![a](b.png)** y",
    ])
    func roundTrips(markdown: String) {
        let spans = InlineMarkdown.spans(in: markdown)
        #expect(InlineMarkdown.spans(in: InlineMarkdown.markdown(for: spans)) == spans)
    }

    /// Every character with its styles' initials.
    private func flags(_ spans: [InlineSpan]) -> [String] {
        spans.flatMap { span in
            span.text.map {
                "\($0)\(span.bold ? "B" : "")\(span.italic ? "I" : "")\(span.strikethrough ? "S" : "")\(span.code ? "C" : "")"
                    + "\(span.subscript ? "~" : "")\(span.superscript ? "^" : "")\(span.highlight ? "=" : "")"
            }
        }
    }

    /// Emphasis that starts and ends at word boundaries reads back as it
    /// was written. (Emphasis changing in the middle of a word, such as
    /// italic "x" straight into bold "a", can't always be written in Markdown:
    /// the closing and opening asterisks run together.)
    @Test(arguments: [
        ([InlineStyle.bold, .italic, .strikethrough, .code], ["a", "*", "~~", "`"]),
        ([InlineStyle.subscript, .superscript, .italic, .code], ["a", "~", "^", "`"]),
        ([InlineStyle.subscript, .superscript, .bold, .strikethrough], ["a", "~", "*", "~~"]),
        ([InlineStyle.subscript, .strikethrough, .italic, .superscript], ["a", "~", "~~", "~~~"]),
        ([InlineStyle.highlight, .strikethrough, .bold, .code], ["a", "=", "==", "~~"]),
    ])
    func roundTripsAnyMixOfEmphasisBetweenWords(styleList: [InlineStyle], words: [String]) {
        func styles(_ bits: Int) -> Set<InlineStyle> {
            Set(styleList.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element))
        }
        for first in words {
            for second in words {
                for third in ["b c"] {
                    for flagBits in 0..<4096 {
                        let spans = [
                            InlineSpan(first, styles: styles(flagBits)),
                            InlineSpan(" "),
                            InlineSpan(second, styles: styles(flagBits >> 4)),
                            InlineSpan(" ", styles: styles(flagBits >> 4).subtracting([.code, .subscript, .superscript])),
                            InlineSpan(third, styles: styles(flagBits >> 8)),
                        ]
                        let markdown = InlineMarkdown.markdown(for: spans)
                        let read = InlineMarkdown.spans(in: markdown)
                        // The same characters with the same styles, except
                        // that spaces may lose theirs.
                        let expected = flags(spans), actual = flags(read)
                        #expect(actual.count == expected.count, "\(spans) → \(markdown)")
                        let mismatched = zip(expected, actual).contains { $0 != $1 && !$0.hasPrefix(" ") }
                        #expect(!mismatched, "\(spans) → \(markdown)")
                    }
                }
            }
        }
    }

    @Test func readsSubscriptAndSuperscript() {
        #expect(InlineMarkdown.spans(in: "H~2~O and x^2^") == [
            InlineSpan("H"), InlineSpan("2", subscript: true), InlineSpan("O and x"), InlineSpan("2", superscript: true),
        ])
        #expect(InlineMarkdown.spans(in: "**x~i~**") == [InlineSpan("x", bold: true), InlineSpan("i", bold: true, subscript: true)])
    }

    @Test func subscriptAndSuperscriptDontSpanWhitespace() {
        for text in ["x^2 + y^2", "a ~ b ~ c", "a ~b c~ d", "~~~~x~~~~", "2^^3^^", "H_2_O", "~~a b~"] {
            #expect(InlineMarkdown.spans(in: text) == [InlineSpan(text)], "\(text)")
        }
        #expect(InlineMarkdown.spans(in: "x~`a b`~") == [InlineSpan("x"), InlineSpan("a b", code: true, subscript: true)])
        #expect(InlineMarkdown.spans(in: "~~a b~~") == [InlineSpan("a b", strikethrough: true)])
        #expect(InlineMarkdown.spans(in: "~~~x~~~") == [InlineSpan("x", strikethrough: true, subscript: true)])
        #expect(InlineMarkdown.spans(in: "~~a ~b~~~") == [InlineSpan("a ", strikethrough: true),
                                                          InlineSpan("b", strikethrough: true, subscript: true)])
        #expect(InlineMarkdown.spans(in: "~x~~~y~~") == [InlineSpan("x", subscript: true), InlineSpan("y", strikethrough: true)])
    }

    @Test func writesSubscriptAndSuperscript() {
        #expect(InlineMarkdown.markdown(for: [InlineSpan("H"), InlineSpan("2", subscript: true), InlineSpan("O")]) == "H~2~O")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("e"), InlineSpan("i pi", superscript: true)]) == "e^i^ ^pi^")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("x", bold: true), InlineSpan("2", bold: true, superscript: true)])
            == "**x^2^**")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("my_var_name")]) == "my_var_name")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("~x~")]) == #"\~x\~"#)
        #expect(InlineMarkdown.markdown(for: [InlineSpan("x^2 + y^2")]) == "x^2 + y^2")
    }

    @Test func readsAndWritesHighlight() {
        #expect(InlineMarkdown.spans(in: "a ==marked text== b") == [
            InlineSpan("a "), InlineSpan("marked text", styles: [.highlight]), InlineSpan(" b"),
        ])
        #expect(InlineMarkdown.spans(in: "==~~**x**~~==") == [InlineSpan("x", styles: [.highlight, .strikethrough, .bold])])
        for text in ["a == b", "x = 1", "===x===", "=x=", "==open"] {
            #expect(InlineMarkdown.spans(in: text) == [InlineSpan(text)], "\(text)")
        }
        #expect(InlineMarkdown.markdown(for: [InlineSpan("x", styles: [.highlight, .strikethrough, .bold])]) == "==~~**x**~~==")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("a == b")]) == "a == b")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("==not==")]) == #"\=\=not\=\="#)
    }

    @Test func keepsHTMLCommentsWhole() {
        #expect(InlineMarkdown.spans(in: "a <!-- *not* ![i](p.png) [l](x) --> *b*") == [
            InlineSpan("a <!-- *not* ![i](p.png) [l](x) --> "), InlineSpan("b", styles: [.italic]),
        ])
        #expect(InlineMarkdown.spans(in: "`<!--` x -->") == [InlineSpan("<!--", styles: [.code]), InlineSpan(" x -->")])
        #expect(InlineMarkdown.markdown(for: [InlineSpan("<!-- *x* -->"), InlineSpan("y", styles: [.bold])])
            == "<!-- *x* -->**y**")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("<!-- *x* --> *z*")]) == #"<!-- *x* --> \*z\*"#)
        #expect(HTMLComment.ranges(in: "a<!--b-->c<!--d") == [1..<9])
        #expect(HTMLComment.opensUnclosed("a <!-- b") && !HTMLComment.opensUnclosed("a <!-- b --> c"))
    }

    @Test func readsLinks() {
        #expect(InlineMarkdown.spans(in: "see [the docs](https://example.com) now") == [
            InlineSpan("see "), InlineSpan("the docs", link: "https://example.com"), InlineSpan(" now"),
        ])
        #expect(InlineMarkdown.spans(in: "[**a** b](notes.md)") == [
            InlineSpan("a", styles: [.bold], link: "notes.md"), InlineSpan(" b", link: "notes.md"),
        ])
        #expect(InlineMarkdown.spans(in: "**[a](x) b**") == [InlineSpan("a", styles: [.bold], link: "x"),
                                                            InlineSpan(" b", styles: [.bold])])
        #expect(InlineMarkdown.spans(in: "[a [b] c](<my file.md> \"title\")") == [InlineSpan("a [b] c", link: "my file.md")])
        #expect(InlineMarkdown.spans(in: "[`a]`](x)") == [InlineSpan("a]", styles: [.code], link: "x")])
        #expect(InlineMarkdown.spans(in: "[ref]()") == [InlineSpan("ref", link: "")])
        #expect(InlineMarkdown.links(in: "a [b](c)") == [InlineMarkdown.Link(range: 2..<8, text: 3..<4, destination: "c")])
        // Emphasis can't pair across a link's brackets.
        #expect(InlineMarkdown.spans(in: "*a [b* c](x)") == [InlineSpan("*a "), InlineSpan("b* c", link: "x")])
    }

    @Test(arguments: ["[]()", "[a]", "[a] (b)", "[a](b", "\\[a](b)", "![a](b.png)", "`[a](b)`", "[a\\](b)"])
    func leavesOtherBracketsAsText(text: String) {
        #expect(InlineMarkdown.spans(in: text).allSatisfy { $0.link == nil })
    }

    @Test func writesLinks() {
        #expect(InlineMarkdown.markdown(for: [InlineSpan("see "), InlineSpan("docs", link: "https://x.org")])
            == "see [docs](https://x.org)")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("a", styles: [.bold], link: "x"), InlineSpan(" b", link: "x")])
            == "[**a** b](x)")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("all", styles: [.bold], link: "x")]) == "**[all](x)**")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("a", link: "my file.md")]) == "[a](<my file.md>)")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("a]", link: "x")]) == #"[a\]](x)"#)
        #expect(InlineMarkdown.markdown(for: [InlineSpan("[not](a link)")]) == "[not](a link)")
        #expect(InlineMarkdown.markdown(for: [InlineSpan("[not](link)")]) == #"\[not\](link)"#)
        #expect(InlineMarkdown.markdown(for: [InlineSpan("a", link: "x"), InlineSpan("b", link: "y")]) == "[a](x)[b](y)")
    }

    @Test(arguments: ["[a](b) and [**c** ~d~](<e f>)", "**[a](b)**", "[a ![i](p.png) b](c)", "x [`[y]`](z) w",
                      "[a](b)*c*"])
    func roundTripsLinks(markdown: String) {
        let spans = InlineMarkdown.spans(in: markdown)
        #expect(InlineMarkdown.spans(in: InlineMarkdown.markdown(for: spans)) == spans, "\(InlineMarkdown.markdown(for: spans))")
    }

    @Test func keepsTheTextWhenEmphasisChangesMidWord() {
        let pieces = ["a", "*", "b c", "**"]
        for first in pieces {
            for second in pieces {
                for flagBits in 0..<16 {
                    let spans = [
                        InlineSpan(first, bold: flagBits & 1 != 0, italic: flagBits & 2 != 0),
                        InlineSpan(second, bold: flagBits & 4 != 0, italic: flagBits & 8 != 0),
                    ]
                    let read = InlineMarkdown.spans(in: InlineMarkdown.markdown(for: spans))
                    #expect(read.map(\.text).joined() == first + second)
                }
            }
        }
    }
}
