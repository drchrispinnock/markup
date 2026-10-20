import AppKit
import MarkupCore

/// Tables (`MarkdownTable`), shown as a grid like a word processor's: an
/// `NSTextTable` whose cells are paragraphs, one per cell, row by row, each
/// with a `NSTextTableBlock` in its paragraph style. The header cells are
/// bold (`.tableHeader`) on a shaded background. Saving writes a Markdown
/// table with its columns lined up.
///
/// The table button and Format > Table insert one, Tab and Shift-Tab move
/// between cells, and Return adds a row. Edits that would merge cells, or
/// split one, aren't allowed.
extension EditorViewController {
    /// The numbers of columns a new table can have.
    static let tableColumnChoices = 1...8

    static let tableBorderColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.25) : NSColor(white: 0, alpha: 0.25)
    }

    static let tableHeaderBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.05)
    }

    // MARK: - Inserting

    /// The sizes of table to insert. Each item's tag is its number of columns.
    static func tableMenu() -> NSMenu {
        let menu = NSMenu(title: "Table")
        for columns in tableColumnChoices {
            let item = menu.addItem(withTitle: columns == 1 ? "1 Column" : "\(columns) Columns",
                                    action: #selector(insertTable(_:)), keyEquivalent: "")
            item.tag = columns
        }
        return menu
    }

    /// The table button: shows the choice of columns below it.
    @objc func showTableMenu(_ sender: NSButton) {
        let menu = Self.tableMenu()
        for item in menu.items {
            item.target = self
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY + 4 : -4), in: sender)
    }

    /// Inserts a table with the menu item's number of columns.
    @objc func insertTable(_ sender: Any?) {
        insertTable(columns: (sender as? NSMenuItem)?.tag ?? 2)
    }

    /// Inserts an empty table of `columns` columns, a header and one row, on
    /// the caret's line if that is an empty paragraph, or else below the
    /// line (or below the table it is in). The first header cell gets the
    /// caret.
    func insertTable(columns: Int) {
        guard !isShowingMarkdown, columns > 0 else { return }
        var line = lineRange(at: textView.selectedRange().location)
        if isTableLine(line) { line = tableLines(around: line).last! }
        let text = NSMutableAttributedString()
        let location: Int
        if contentsRange(of: line).length == 0, !isTableLine(line) {
            location = line.location
        } else if NSMaxRange(contentsRange(of: line)) == NSMaxRange(line) {
            // The last line, with no newline to end it.
            location = NSMaxRange(line)
            text.append(NSAttributedString(string: "\n", attributes: storage.attributes(at: line.location, effectiveRange: nil)))
        } else {
            location = NSMaxRange(line)
        }
        let separated = isTableLine(line)
        if separated {
            // A blank line keeps the tables apart.
            text.append(NSAttributedString(string: "\n", attributes: BlockStyle.paragraph.attributes))
        }
        let start = location + text.length
        text.append(Self.tableText(MarkdownTable.Table(columns: columns), imageFolders: imageFolders))
        replaceCharacters(in: NSRange(location: location, length: 0), with: text)
        undoManager?.setActionName("Insert Table")
        emptyLineStyle = nil
        select(cell: lineRange(at: start))
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Building tables

    /// `table` as the editor shows it: one paragraph per cell, each ending
    /// in a newline, so even an empty cell has a character.
    static func tableText(_ table: MarkdownTable.Table, imageFolders: [URL]) -> NSAttributedString {
        let textTable = makeTextTable(columns: table.header.count)
        let text = NSMutableAttributedString()
        for (row, cells) in ([table.header] + table.rows).enumerated() {
            for (column, cell) in cells.enumerated() {
                let attributes = cellAttributes(in: textTable, row: row, column: column,
                                                alignment: table.alignments[column].textAlignment)
                text.append(inlineText(cell + "\n", attributes: attributes, imageFolders: imageFolders))
            }
        }
        return text
    }

    /// A table as wide as the text, with thin borders between its cells.
    static func makeTextTable(columns: Int) -> NSTextTable {
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setContentWidth(100, type: .percentageValueType)
        return table
    }

    /// The attributes of a cell's text: the cell's block, the column's
    /// alignment and, in the header, bold.
    static func cellAttributes(in table: NSTextTable, row: Int, column: Int,
                               alignment: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        block.setWidth(1, type: .absoluteValueType, for: .border)
        block.setBorderColor(tableBorderColor)
        block.setWidth(6, type: .absoluteValueType, for: .padding)
        block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(8, type: .absoluteValueType, for: .padding, edge: .maxX)
        if row == 0 { block.backgroundColor = tableHeaderBackground }
        let paragraph = NSMutableParagraphStyle()
        paragraph.textBlocks = [block]
        paragraph.alignment = alignment
        var attributes = BlockStyle.table.attributes
        attributes[.paragraphStyle] = paragraph
        attributes[.tableHeader] = row == 0 ? true : nil
        return attributes.withInlineStyles([])
    }

    // MARK: - Finding cells

    /// The table cell that the paragraph at `location` is, if it is one.
    func tableBlock(at location: Int) -> NSTextTableBlock? {
        guard location < storage.length else { return nil }
        return (storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?
            .textBlocks.last as? NSTextTableBlock
    }

    /// Whether `line` is a table cell.
    func isTableLine(_ line: NSRange) -> Bool {
        line.length > 0 && tableBlock(at: line.location) != nil
    }

    /// The cells of the table that the cell `line` is in, in order.
    func tableLines(around line: NSRange) -> [NSRange] {
        guard let table = tableBlock(at: line.location)?.table else { return [line] }
        func isInTable(_ line: NSRange) -> Bool { line.length > 0 && tableBlock(at: line.location)?.table === table }
        var first = line
        while first.location > 0 {
            let previous = lineRange(at: first.location - 1)
            guard isInTable(previous) else { break }
            first = previous
        }
        var lines = [first]
        while NSMaxRange(lines.last!) < storage.length {
            let next = lineRange(at: NSMaxRange(lines.last!))
            guard isInTable(next) else { break }
            lines.append(next)
        }
        return lines
    }

    private func columns(of cells: [NSRange]) -> Int {
        max(1, cells.first.flatMap { tableBlock(at: $0.location)?.table.numberOfColumns } ?? 1)
    }

    /// The Markdown of a table's cells.
    func markdownTable(of cells: [NSRange]) -> MarkdownTable.Table {
        let columns = columns(of: cells)
        var rows = stride(from: 0, to: cells.count, by: columns).map { start in
            cells[start..<min(start + columns, cells.count)].map { inlineMarkdown(in: contentsRange(of: $0)) }
        }
        rows[rows.count - 1] += Array(repeating: "", count: columns - rows[rows.count - 1].count)
        let alignments = cells.prefix(columns).map { cell in
            TableAlignment(
                (storage.attribute(.paragraphStyle, at: cell.location, effectiveRange: nil) as? NSParagraphStyle)?.alignment ?? .natural)
        }
        return MarkdownTable.Table(header: rows[0], alignments: alignments, rows: Array(rows.dropFirst()))
    }

    /// Selects a cell's text, so typing replaces it, or puts the caret in an
    /// empty cell.
    private func select(cell: NSRange) {
        let contents = contentsRange(of: cell)
        textView.setSelectedRange(contents)
        textView.scrollRangeToVisible(contents)
        updateForSelection()
    }

    // MARK: - Commands

    /// Adds an empty row below row `row` of the table whose cells are
    /// `cells`, and puts the caret in its first cell.
    private func addTableRow(below row: Int, of cells: [NSRange]) {
        let columns = columns(of: cells)
        let lastCell = cells[min(cells.count, (row + 1) * columns) - 1]
        guard let block = tableBlock(at: lastCell.location) else { return }
        let text = NSMutableAttributedString()
        for column in 0..<columns {
            let alignment = (storage.attribute(.paragraphStyle, at: cells[column].location, effectiveRange: nil)
                as? NSParagraphStyle)?.alignment ?? .natural
            text.append(NSAttributedString(string: "\n", attributes: Self.cellAttributes(
                in: block.table, row: row + 1, column: column, alignment: alignment)))
        }
        let location = NSMaxRange(lastCell)
        replaceCharacters(in: NSRange(location: location, length: 0), with: text)
        undoManager?.setActionName("Add Row")
        select(cell: lineRange(at: location))
    }

    /// Tab and Shift-Tab in a table select the next or previous cell. Tab in
    /// the last cell adds a row. Returns false outside tables.
    func moveToCell(forward: Bool) -> Bool {
        let line = lineRange(at: textView.selectedRange().location)
        guard isTableLine(line) else { return false }
        let cells = tableLines(around: line)
        let index = cells.firstIndex { $0.location == line.location }!
        let target = forward ? index + 1 : index - 1
        if cells.indices.contains(target) {
            select(cell: cells[target])
        } else if target == cells.count {
            addTableRow(below: (cells.count - 1) / columns(of: cells), of: cells)
        }
        return true
    }

    /// Return in a table adds a row below the caret's row. In an empty last
    /// row it ends the table instead: the row becomes an empty paragraph.
    func insertNewlineInTable() -> Bool {
        let selection = textView.selectedRange()
        let line = lineRange(at: selection.location)
        guard isTableLine(line) else { return false }
        let cells = tableLines(around: line)
        let columns = columns(of: cells)
        let row = cells.firstIndex { $0.location == line.location }! / columns
        let rowCells = cells[(row * columns)..<min(cells.count, (row + 1) * columns)]
        let isLastRow = rowCells.last?.location == cells.last?.location
        guard row > 0, isLastRow, rowCells.allSatisfy({ contentsRange(of: $0).length == 0 }) else {
            addTableRow(below: row, of: cells)
            return true
        }
        let rowRange = NSRange(location: rowCells.first!.location, length: NSMaxRange(rowCells.last!) - rowCells.first!.location)
        replaceCharacters(in: rowRange, with: NSAttributedString(string: "\n", attributes: BlockStyle.paragraph.attributes))
        undoManager?.setActionName("End Table")
        textView.setSelectedRange(NSRange(location: rowRange.location, length: 0))
        updateForSelection()
        return true
    }

    // MARK: - Keeping tables whole

    /// Whether to let the text view replace `range` with `replacement`. Within
    /// one cell anything goes, except that a newline would split the cell,
    /// so it is typed as a space. Otherwise an edit may remove whole rows,
    /// but not merge cells or join a paragraph onto one.
    func allowsTableEdit(in range: NSRange, replacement: String) -> Bool {
        let touched = lineRanges(in: range).filter(isTableLine)
        let end = NSMaxRange(range)
        // Deleting the newline before a table from inside a line would join
        // that line onto the first cell.
        if range.length > 0, end < storage.length, isTableLine(lineRange(at: end)), !isTableLine(lineRange(at: end - 1)),
           lineRange(at: range.location).location != range.location {
            return false
        }
        guard let first = touched.first else { return true }
        if touched.count == 1, range.location >= first.location, end <= NSMaxRange(contentsRange(of: first)) {
            guard replacement.contains("\n") else { return true }
            let text = replacement.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
            replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: textView.typingAttributes))
            textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
            return false
        }
        // Every cell touched must go, and with it the rest of its row.
        guard touched.allSatisfy({ $0.location >= range.location && NSMaxRange($0) <= end }) else { return false }
        var checked: Set<Int> = []
        for line in touched {
            let cells = tableLines(around: line)
            guard checked.insert(cells[0].location).inserted else { continue }
            let columns = columns(of: cells)
            for (index, cell) in cells.enumerated() where cell.location >= range.location && NSMaxRange(cell) <= end {
                let row = cells[(index / columns * columns)..<min(cells.count, (index / columns + 1) * columns)]
                guard row.allSatisfy({ $0.location >= range.location && NSMaxRange($0) <= end }) else { return false }
            }
        }
        return true
    }

    /// Gives each cell of the tables that `range` touches the block for its
    /// place, row by row, and bold header cells. Called after every edit, so
    /// adding or removing rows keeps the grid in order.
    func updateTables(in range: NSRange) {
        var updated: Set<Int> = []
        for line in lineRanges(in: range) where isTableLine(line) {
            let cells = tableLines(around: line)
            guard updated.insert(cells[0].location).inserted, let table = tableBlock(at: cells[0].location)?.table
            else { continue }
            let columns = columns(of: cells)
            for (index, cell) in cells.enumerated() {
                let (row, column) = (index / columns, index % columns)
                let block = tableBlock(at: cell.location)
                let isHeader = row == 0
                guard block?.startingRow != row || block?.startingColumn != column
                        || (storage.attribute(.tableHeader, at: cell.location, effectiveRange: nil) != nil) != isHeader
                else { continue }
                let alignment = (storage.attribute(.paragraphStyle, at: cell.location, effectiveRange: nil)
                    as? NSParagraphStyle)?.alignment ?? .natural
                let attributes = Self.cellAttributes(in: table, row: row, column: column, alignment: alignment)
                changeAttributes(in: cell) {
                    storage.addAttribute(.paragraphStyle, value: attributes[.paragraphStyle]!, range: cell)
                    if isHeader {
                        storage.addAttribute(.tableHeader, value: true, range: cell)
                    } else {
                        storage.removeAttribute(.tableHeader, range: cell)
                    }
                    storage.applyInlineStyles(in: cell)
                }
            }
        }
    }

    /// Turns paragraphs around the edit that form a Markdown table, typed or
    /// pasted, into a table. Only an edit that adds a newline does this, so
    /// a table being typed converts when Return ends its delimiter row. The
    /// caret goes to the first cell after the header, adding a row if there
    /// is none.
    func convertTables(after edit: NSRange) {
        guard NSMaxRange(edit) <= storage.length, (storage.string as NSString).substring(with: edit).contains("\n")
        else { return }
        var lines: [NSRange] = []
        var location = lineRange(at: edit.location).location
        // The line above may be a header whose delimiter row was just typed.
        if location > 0 { location = lineRange(at: location - 1).location }
        while location < storage.length, location <= NSMaxRange(edit) {
            let line = lineRange(at: location)
            lines.append(line)
            location = NSMaxRange(line)
        }
        let isParagraph = { (line: NSRange) in
            line.length > 0 && !self.isTableLine(line) && self.listItem(at: line) == nil
                && self.storage.blockStyle(at: line.location) == .paragraph
        }
        let texts = lines.map { isParagraph($0) ? inlineMarkdown(in: contentsRange(of: $0)) : "" }
        var index = 0
        while index < lines.count {
            guard isParagraph(lines[index]),
                  let count = MarkdownTable.rowCount(startingAt: index, in: texts, startsBlock: { !isParagraph(lines[$0]) }),
                  var table = MarkdownTable.table(from: texts[index..<index + count].map { $0 })
            else {
                index += 1
                continue
            }
            if table.rows.isEmpty { table.rows = [Array(repeating: "", count: table.header.count)] }
            // Each cell ends in a newline, which takes the place of the last
            // line's.
            let first = lines[index], last = lines[index + count - 1]
            let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
            let text = Self.tableText(table, imageFolders: imageFolders)
            replaceCharacters(in: range, with: text)
            undoManager?.setActionName("Table")
            let cells = tableLines(around: lineRange(at: first.location))
            select(cell: cells[min(columns(of: cells), cells.count - 1)])
            return
        }
    }
}

private extension TableAlignment {
    init(_ alignment: NSTextAlignment) {
        switch alignment {
        case .left: self = .left
        case .center: self = .center
        case .right: self = .right
        default: self = .none
        }
    }

    var textAlignment: NSTextAlignment {
        switch self {
        case .none: .natural
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}
