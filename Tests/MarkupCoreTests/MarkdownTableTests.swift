import Testing
@testable import MarkupCore

@Suite struct MarkdownTableTests {
    private func texts(_ row: String) -> [String] {
        let units = Array(row.utf16)
        return MarkdownTable.cells(in: row).map { String(decoding: units[$0], as: UTF16.self) }
    }

    @Test func cellsAreBetweenThePipes() {
        #expect(texts("| a | b |") == [" a ", " b "])
        #expect(texts("a | b") == ["a ", " b"])
        #expect(texts("|  |  |") == ["  ", "  "])
        #expect(texts("| a \\| b | c |") == [" a \\| b ", " c "])
        #expect(texts("| é | 😀 |") == [" é ", " 😀 "])
    }

    @Test(arguments: ["| --- | --- |", "---|---", "|:-|-:|:-:|", "| - |"])
    func recognisesDelimiterRows(row: String) {
        #expect(MarkdownTable.isDelimiterRow(row))
    }

    @Test(arguments: ["---", "| a | --- |", "| |", "| -- - |", "|::|"])
    func rejectsOtherRows(row: String) {
        #expect(!MarkdownTable.isDelimiterRow(row))
    }

    @Test func readsATableAsTableLines() {
        let lines = MarkdownCodec.lines(fromMarkdown: "Intro\n| a | b |\n| - | - |\n| 1 | **2** |\n\nAfter")
        #expect(lines == [
            Line(style: .paragraph, text: "Intro"),
            Line(style: .table, text: "| a | b |"),
            Line(style: .table, text: "| - | - |"),
            Line(style: .table, text: "| 1 | **2** |"),
            Line(style: .paragraph, text: ""),
            Line(style: .paragraph, text: "After"),
        ])
    }

    @Test func tableEndsAtALineWithoutAPipeOrAnotherBlock() {
        let lines = MarkdownCodec.lines(fromMarkdown: "a|b\n-|-\nno pipe\n| x |\n|-|\n- item | x")
        #expect(lines.map(\.style) == [.table, .table, .paragraph, .table, .table, .paragraph])
        #expect(lines.last?.list != nil)
    }

    @Test(arguments: ["| a | b |\n| - |", "| a |\ntext", "- a | b\n| - | - |", "| a |"])
    func isNotATableWithoutAMatchingDelimiterRow(markdown: String) {
        #expect(!MarkdownCodec.lines(fromMarkdown: markdown).contains { $0.style == .table })
    }

    @Test(arguments: ["| a | b |\n| :-- | --: |\n| *x* | `y` \\| z |", "x\n\n|a|\n|-|\n|1|\n|2|\n\n# After"])
    func roundTrips(markdown: String) {
        #expect(MarkdownCodec.markdown(from: MarkdownCodec.lines(fromMarkdown: markdown)) == markdown)
    }

    @Test func readsCellsAndAlignments() {
        let table = MarkdownTable.table(from: ["| a | b \\| c | d |", "|:--|:-:|--:|", "| 1 |", "| 2 | 3 | 4 | 5 |"])
        #expect(table == MarkdownTable.Table(header: ["a", "b | c", "d"], alignments: [.left, .center, .right],
                                             rows: [["1", "", ""], ["2", "3", "4"]]))
    }

    @Test func writesTablesWithColumnsLinedUp() {
        let table = MarkdownTable.Table(header: ["Name", "n"], alignments: [.none, .right], rows: [["a | b", "**10**"]])
        #expect(MarkdownTable.lines(for: table) == [
            "| Name   | n      |",
            "| ------ | -----: |",
            "| a \\| b | **10** |",
        ])
        #expect(MarkdownTable.table(from: MarkdownTable.lines(for: table)) == table)
    }

    @Test func emptyTable() {
        let lines = MarkdownTable.lines(for: MarkdownTable.Table(columns: 2))
        #expect(lines == ["|     |     |", "| --- | --- |", "|     |     |"])
        #expect(MarkdownCodec.lines(fromMarkdown: lines.joined(separator: "\n")).allSatisfy { $0.style == .table })
    }
}
