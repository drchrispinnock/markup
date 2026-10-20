/// GitHub Flavored Markdown tables:
///
///     | Name | Count |
///     | ---- | ----: |
///     | one  | 1     |
///
/// A table is a header row and a delimiter row with the same number of
/// cells, then the body: the rows that follow, up to a blank line, a line
/// without a pipe or the start of another block. The pipes at the start and
/// end of a row are optional, and a pipe escaped with a backslash is part of
/// its cell.
public enum MarkdownTable {
    /// The cells of a row, as UTF-16 offset ranges between its pipes, with
    /// the spaces around their text.
    public static func cells(in row: some StringProtocol) -> [Range<Int>] {
        let units = Array(row.utf16)
        let pipes = units.indices.filter { units[$0] == pipe && ($0 == 0 || units[$0 - 1] != backslash) }
        var start = 0
        var end = units.count
        if let first = units.firstIndex(where: { !isSpace($0) }), pipes.first == first { start = first + 1 }
        if let last = units.lastIndex(where: { !isSpace($0) }), pipes.last == last, last >= start { end = last }
        guard start <= end else { return [] }
        var cells: [Range<Int>] = []
        var cellStart = start
        for pipe in pipes where pipe >= start && pipe < end {
            cells.append(cellStart..<pipe)
            cellStart = pipe + 1
        }
        cells.append(cellStart..<end)
        return cells
    }

    /// Whether `row` is a delimiter row: cells of dashes, with a colon at
    /// either end for alignment, such as "| --- | :-: |".
    public static func isDelimiterRow(_ row: some StringProtocol) -> Bool {
        guard row.contains("|") else { return false }
        let units = Array(row.utf16)
        let cells = cells(in: row)
        return !cells.isEmpty && cells.allSatisfy { cell in
            var text = units[cell].drop(while: isSpace)
            while let last = text.last, isSpace(last) { text = text.dropLast() }
            if text.first == colon { text = text.dropFirst() }
            if text.last == colon { text = text.dropLast() }
            return !text.isEmpty && text.allSatisfy { $0 == dash }
        }
    }

    /// The number of lines in the table starting at `start` in `lines`, or
    /// nil if no table starts there. `startsBlock` says whether a line starts
    /// another kind of block (a heading, list item or code fence), which
    /// can't be part of a table.
    public static func rowCount(startingAt start: Int, in lines: [some StringProtocol],
                                startsBlock: (Int) -> Bool) -> Int? {
        guard start + 1 < lines.count, lines[start].contains("|"), !startsBlock(start), !startsBlock(start + 1),
              isDelimiterRow(lines[start + 1]),
              cells(in: lines[start]).count == cells(in: lines[start + 1]).count else { return nil }
        var end = start + 2
        while end < lines.count, lines[end].contains("|"), !startsBlock(end) { end += 1 }
        return end - start
    }

    /// A table's contents: the Markdown of each cell, with any pipe in it
    /// unescaped, and each column's alignment.
    public struct Table: Equatable, Sendable {
        public var header: [String]
        public var alignments: [TableAlignment]
        public var rows: [[String]]

        public init(header: [String], alignments: [TableAlignment], rows: [[String]]) {
            self.header = header
            self.alignments = alignments
            self.rows = rows
        }

        /// An empty table of `columns` columns, with one row below the header.
        public init(columns: Int) {
            self.init(header: Array(repeating: "", count: columns), alignments: Array(repeating: .none, count: columns),
                      rows: [Array(repeating: "", count: columns)])
        }
    }

    /// The table that `lines` are: a header, a delimiter row, then rows.
    /// Rows have as many cells as the header, as GitHub shows them: missing
    /// cells are empty and extra ones are left out.
    public static func table(from lines: [some StringProtocol]) -> Table? {
        guard lines.count >= 2, isDelimiterRow(lines[1]) else { return nil }
        let header = cellTexts(in: lines[0])
        let alignments = cellTexts(in: lines[1]).map(TableAlignment.init(delimiter:))
        guard header.count == alignments.count else { return nil }
        let rows = lines.dropFirst(2).map { line in
            let cells = cellTexts(in: line).prefix(header.count)
            return Array(cells) + Array(repeating: "", count: header.count - cells.count)
        }
        return Table(header: header, alignments: alignments, rows: rows)
    }

    /// The Markdown lines of `table`, with the columns padded to line up.
    public static func lines(for table: Table) -> [String] {
        let escaped = ([table.header] + table.rows).map { $0.map(escape) }
        let widths = table.header.indices.map { column in
            max(3, escaped.map { $0[column].count }.max() ?? 0)
        }
        func row(_ cells: [String]) -> String {
            "| " + zip(cells, widths).map { $0 + String(repeating: " ", count: $1 - $0.count) }.joined(separator: " | ") + " |"
        }
        let delimiter = "|" + zip(table.alignments, widths).map { " " + $0.delimiter(width: $1) + " |" }.joined()
        return [row(escaped[0]), delimiter] + escaped.dropFirst().map(row)
    }

    /// The text of each cell of `row`, without the spaces around it, and
    /// with escaped pipes unescaped.
    private static func cellTexts(in row: some StringProtocol) -> [String] {
        let units = Array(row.utf16)
        return cells(in: row).map { cell in
            String(decoding: units[cell], as: UTF16.self).trimmingSpaces.replacingAll("\\|", with: "|")
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingAll("|", with: "\\|")
    }

    private static let pipe = UInt16(UInt8(ascii: "|"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let colon = UInt16(UInt8(ascii: ":"))
    private static let dash = UInt16(UInt8(ascii: "-"))

    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == UInt16(UInt8(ascii: " ")) || unit == UInt16(UInt8(ascii: "\t"))
    }
}

/// How a table column's text is aligned, from the colons in its delimiter.
public enum TableAlignment: Sendable {
    case none
    case left
    case center
    case right

    init(delimiter cell: String) {
        switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
        case (true, true): self = .center
        case (true, false): self = .left
        case (false, true): self = .right
        case (false, false): self = .none
        }
    }

    /// The delimiter cell for a column `width` characters wide.
    func delimiter(width: Int) -> String {
        switch self {
        case .none: String(repeating: "-", count: width)
        case .left: ":" + String(repeating: "-", count: width - 1)
        case .center: ":" + String(repeating: "-", count: width - 2) + ":"
        case .right: String(repeating: "-", count: width - 1) + ":"
        }
    }
}

private extension String {
    var trimmingSpaces: String {
        let start = firstIndex { $0 != " " && $0 != "\t" } ?? endIndex
        let end = lastIndex { $0 != " " && $0 != "\t" }.map(index(after:)) ?? start
        return start < end ? String(self[start..<end]) : ""
    }

    func replacingAll(_ target: String, with replacement: String) -> String {
        split(separator: target, omittingEmptySubsequences: false).joined(separator: replacement)
    }
}
