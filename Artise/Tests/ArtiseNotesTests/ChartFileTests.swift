//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

/// Chart files read as the editor's fields and written back changing only what changed.
struct ChartFileTests {
    /// The example from family-wiki's docs/notes-api.md, comments and all.
    static let example = """
    title: Ventas por mes
    type: bar            # bar | line | area | pie | donut | stacked | kpi | table
    unit: MXN            # optional
    caption: Sin IVA     # optional
    data:
      columns: [Mes, Ventas]          # the labels' column, then one per series (at most 8)
      rows:
        - [2026-05, 12000]
        - [2026-06, 15400]
    series: [Ventas]     # optional: only these columns
    colors: ["#22408A"]  # optional: these first, then the workspace's palette
    
    """
    
    static let sourced = """
    title: Cobros con tarjeta
    type: line
    source:
      records: payment          # a record type
      where: {method: card}     # optional filters
      period: last 6 months
      x: month
      y: sum(amount)
      group: method
    
    """
    
    // MARK: - Reading
    
    /// Every field of the documented example is read: text, the table (labels as text, numbers as numbers), lists.
    @Test
    func theDocumentedExampleIsRead() throws {
        let draft = try ChartFile.read(Self.example).original
        
        #expect(draft.title == "Ventas por mes")
        #expect(draft.chartType == .bar)
        #expect(draft.unit == "MXN")
        #expect(draft.caption == "Sin IVA")
        #expect(draft.mode == .data)
        #expect(draft.columns == ["Mes", "Ventas"])
        #expect(draft.rows == [[.text("2026-05"), .number(12000)], [.text("2026-06"), .number(15400)]])
        #expect(draft.series == ["Ventas"])
        #expect(draft.colors == ["#22408A"])
    }
    
    /// A chart that reads the chat's records: its source, filters included.
    @Test
    func aSourcedChartIsRead() throws {
        let draft = try ChartFile.read(Self.sourced).original
        
        #expect(draft.mode == .source)
        #expect(draft.source == ChartSource(records: "payment", filters: [ChartFilter(field: "method", value: "card")],
                                            period: "last 6 months", x: "month", y: "sum(amount)", group: "method"))
    }
    
    /// What Ari's `make_chart` writes (PyYAML: quoted labels, block lists, the list at the key's indentation) reads too.
    @Test
    func pyYAMLsOwnStyleIsRead() throws {
        let text = """
        title: 'Ventas: octubre'
        type: pie
        data:
          columns:
          - Método
          - Total
          rows:
          - ['tarjeta', 1200.5]
          - ["efectivo", "1,300"]
          - - transferencia
            - -0
        """
        let draft = try ChartFile.read(text).original
        
        #expect(draft.title == "Ventas: octubre")
        #expect(draft.columns == ["Método", "Total"])
        #expect(draft.rows == [[.text("tarjeta"), .number(1200.5)], [.text("efectivo"), .number(1300)], [.text("transferencia"), .number(0)]])
    }
    
    /// A list that goes on over several lines is read whole.
    @Test
    func aFlowListOverSeveralLinesIsRead() throws {
        let draft = try ChartFile.read("title: A\ndata:\n  columns: [Mes,\n    Ventas, Gastos]\n  rows:\n    - [1, 2, 3]\n").original
        
        #expect(draft.columns == ["Mes", "Ventas", "Gastos"])
    }
    
    /// A field the server doesn't know, or a known one in a shape the form can't show, opens as text instead.
    @Test
    func whatTheFormCantShowIsSaid() {
        #expect(throws: ChartFileError.unknownFields(["legend"])) { try ChartFile.read("title: A\nlegend: true\n") }
        #expect(throws: ChartFileError.unexpectedShape("data")) { try ChartFile.read("title: A\ndata: some text\n") }
        #expect(throws: ChartFileError.self) { try ChartFile.read("title: \"A\n") }
        #expect(throws: ChartFileError.self) { try ChartFile.read("title: A\n  type: bar\n") }
    }
    
    // MARK: - Writing
    
    /// Nothing changed: the file comes back exactly as it was.
    @Test
    func anUnchangedChartKeepsItsText() throws {
        let file = try ChartFile.read(Self.example)
        
        #expect(file.writing(file.original) == Self.example)
    }
    
    /// A new title rewrites the title's line only: the other fields keep their order and comments.
    @Test
    func aChangedFieldRewritesOnlyItsLines() throws {
        let file = try ChartFile.read(Self.example)
        var draft = file.original
        draft.title = "Ventas: noviembre"
        
        let text = file.writing(draft)
        
        #expect(text == Self.example.replacingOccurrences(of: "title: Ventas por mes", with: "title: \"Ventas: noviembre\""))
    }
    
    /// A new row rewrites the table (numbers plain, a label that looks like a date quoted) and nothing else.
    @Test
    func aNewRowRewritesTheTable() throws {
        let file = try ChartFile.read(Self.example)
        var draft = file.original
        draft.rows.append([.text("2026-07"), .number(1234.5)])
        
        let text = file.writing(draft)
        
        #expect(text.contains("""
        data:
          columns: [Mes, Ventas]
          rows:
            - ["2026-05", 12000]
            - ["2026-06", 15400]
            - ["2026-07", 1234.5]
        series: [Ventas]     # optional: only these columns
        """))
        #expect(text.hasPrefix("title: Ventas por mes\ntype: bar            # bar"))
        #expect(try ChartFile.read(text).original == draft)
    }
    
    /// A field emptied goes; a field the file didn't have is added at the end, in the usual order.
    @Test
    func fieldsAreRemovedAndAdded() throws {
        let file = try ChartFile.read(Self.example)
        var draft = file.original
        draft.unit = ""
        draft.type = "kpi"
        draft.comparesPrevious = true
        
        let text = file.writing(draft)
        
        #expect(!text.contains("unit:"))
        #expect(text.contains("type: kpi\n"))
        #expect(text.hasSuffix("colors: [\"#22408A\"]  # optional: these first, then the workspace's palette\ncompare: previous\n"))
    }
    
    /// Switching to records drops the table and writes the source, filters as fields.
    @Test
    func switchingToRecordsWritesTheSource() throws {
        let file = try ChartFile.read(Self.example)
        var draft = file.original
        draft.mode = .source
        draft.series = []
        draft.source = ChartSource(records: "payment", filters: [ChartFilter(field: "method", value: "card")], period: "2026", x: "month",
                                   y: "sum(amount)")
        
        let text = file.writing(draft)
        
        #expect(!text.contains("data:"))
        #expect(text.contains("""
        source:
          records: payment
          where: {method: card}
          period: "2026"
          x: month
          y: sum(amount)
        """))
        #expect(try ChartFile.read(text).original.source == draft.source)
    }
    
    /// A new chart: a title, a bar chart and one row to fill in, in the person's language.
    @Test
    func aNewChartIsWritten() throws {
        let text = ChartFile.new(title: "Ventas", labelsColumn: "Etiqueta", valuesColumn: "Valor")
        
        #expect(text == "title: Ventas\ntype: bar\ndata:\n  columns: [Etiqueta, Valor]\n  rows:\n    - [\"\", 0]\n")
        #expect(try ChartChecks.problem(ChartFile.read(text).original) == nil)
    }
    
    // MARK: - Numbers
    
    /// Numbers typed the way each language writes them are saved plain.
    @Test
    func numbersAreReadInThePersonsWay() {
        #expect(ChartNumbers.parse("1,234.50", locale: Locale(identifier: "es_MX")) == 1234.5)
        #expect(ChartNumbers.parse("1.234,50", locale: Locale(identifier: "pt_BR")) == 1234.5)
        #expect(ChartNumbers.parse("$1,200", locale: Locale(identifier: "en_US")) == 1200)
        #expect(ChartNumbers.parse("1234.5", locale: Locale(identifier: "pt_BR")) == 1234.5)
        #expect(ChartNumbers.parse("abc", locale: Locale(identifier: "es_MX")) == nil)
        #expect(ChartCell.number(1234.5).plain == "1234.5")
        #expect(ChartCell.number(12000).plain == "12000")
    }
    
    /// Cells copied from a spreadsheet replace the table, the first line naming the columns.
    @Test
    func aSpreadsheetIsPasted() {
        var draft = ChartDraft(title: "A", columns: ["Mes", "Ventas"], rows: [])
        
        draft.paste("Mes\tVentas\tGastos\nmayo\t1.234,5\t10\njunio\t2000\t", locale: Locale(identifier: "pt_BR"))
        
        #expect(draft.columns == ["Mes", "Ventas", "Gastos"])
        #expect(draft.rows == [[.text("mayo"), .number(1234.5), .number(10)], [.text("junio"), .number(2000), .text("")]])
    }
    
    // MARK: - Checks
    
    /// The same checks as the server, so a chart that can't be drawn can't be saved.
    @Test
    func theServersChecksAreMade() {
        let good = ChartDraft(title: "A", columns: ["Mes", "Ventas"], rows: [[.text("mayo"), .number(1)]])
        #expect(ChartChecks.problem(good) == nil)
        
        var draft = good
        draft.title = " "
        #expect(ChartChecks.problem(draft) == .title)
        
        draft = good
        draft.type = "radar"
        #expect(ChartChecks.problem(draft) == .unknownType("radar"))
        
        draft = good
        draft.columns = ["Mes"] + (1...9).map { "S\($0)" }
        draft.rows = [[.text("mayo")] + Array(repeating: .number(1), count: 9)]
        #expect(ChartChecks.problem(draft) == .tooManySeries(9))
        
        draft = good
        draft.rows.append([.text("junio"), .text("mucho")])
        #expect(ChartChecks.problem(draft) == .notANumber(row: 2, column: "Ventas", value: "mucho"))
        draft.type = "table"
        #expect(ChartChecks.problem(draft) == nil)
        
        draft = good
        draft.type = "pie"
        draft.rows.append([.text("junio"), .number(-3)])
        #expect(ChartChecks.problem(draft) == .negative(type: "pie"))
        
        draft = good
        draft.type = "donut"
        draft.addColumn(named: "Gastos")
        #expect(ChartChecks.problem(draft) == .oneSeries(type: "donut", count: 2))
        
        draft = good
        draft.comparesPrevious = true
        #expect(ChartChecks.problem(draft) == .compareNotKPI)
        
        draft = good
        draft.rows[0].append(.number(2))
        #expect(ChartChecks.problem(draft) == .rowLength(row: 1, expected: 2))
        
        draft = good
        draft.columns = ["Mes", "Mes"]
        #expect(ChartChecks.problem(draft) == .names)
        
        draft = good
        draft.mode = .source
        draft.source = ChartSource(records: "")
        #expect(ChartChecks.problem(draft) == .source)
        
        #expect(ChartChecks.problem(good, fileText: String(repeating: "x", count: 70000)) == .tooBig)
    }
    
    /// A renamed column stays drawn; a removed one leaves the series.
    @Test
    func columnsAreRenamedAndRemoved() {
        var draft = ChartDraft(title: "A", series: ["Ventas"], columns: ["Mes", "Ventas", "Gastos"], rows: [[.text("mayo"), .number(1), .number(2)]])
        
        draft.renameColumn(at: 1, to: "Ingresos")
        #expect(draft.series == ["Ingresos"])
        draft.removeColumn(at: 1)
        #expect(draft.columns == ["Mes", "Gastos"])
        #expect(draft.rows == [[.text("mayo"), .number(2)]])
        #expect(draft.series.isEmpty)
    }
}
