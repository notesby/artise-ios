//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

/// Dashboards read as text, charts and columns, with the server's problems, and the text edits the layout makes.
struct DashboardLayoutTests {
    /// The example from family-wiki's docs/notes-api.md.
    static let example = """
    ---
    type: dashboard
    title: Octubre 2026
    theme: {accent: "#22408A", palette: ["#22408A", "#EB6834"], mode: auto}
    ---
    ## Ventas
    ![[charts/ventas.chart]]
    ::: columns
    ![[charts/cobros.chart]]
    ![[clientes.chart]]
    :::
    Text, lists and tables as in any note.
    """
    
    static let paths: Set = ["charts/ventas.chart", "charts/cobros.chart", "charts/clientes.chart"]
    
    /// Its parts in order, each with its lines, and its header's title and theme.
    @Test
    func theDocumentedExampleIsRead() throws {
        let layout = try #require(DashboardLayout.parse(Self.example))
        
        #expect(layout.title == "Octubre 2026")
        #expect(layout.theme == DashboardTheme(accent: "#22408A", palette: ["#22408A", "#EB6834"], mode: .auto))
        #expect(layout.blocks == [
            .item(.text(5...5)),
            .item(.chart(ref: "charts/ventas.chart", line: 6)),
            .columns(open: 7, close: 10, items: [.chart(ref: "charts/cobros.chart", line: 8), .chart(ref: "clientes.chart", line: 9)]),
            .item(.text(11...11))
        ])
        #expect(layout.problems(chartPaths: Self.paths).isEmpty)
        #expect(!layout.isReport)
    }
    
    /// Only a note whose header says dashboard (or report) is one.
    @Test
    func otherNotesArentDashboards() throws {
        #expect(DashboardLayout.parse("# Lista\n![[charts/a.chart]]") == nil)
        #expect(DashboardLayout.parse("---\ntype: person\n---\nAna") == nil)
        #expect(try #require(DashboardLayout.parse("---\ntype: report\n---\n")).isReport)
    }
    
    /// A bare name is a chart in `charts/`; a path is as written.
    @Test
    func embedsNameCharts() {
        #expect(DashboardLayout.chartPath("clientes.chart", in: Self.paths) == "charts/clientes.chart")
        #expect(DashboardLayout.chartPath("charts/ventas.chart", in: Self.paths) == "charts/ventas.chart")
        #expect(DashboardLayout.chartPath("otro.chart", in: Self.paths) == nil)
        #expect(DashboardLayout.chartRef("  ![[charts/a.chart|Ventas]] ") == "charts/a.chart")
        #expect(DashboardLayout.chartRef("![[foto.jpg]]") == nil)
        #expect(DashboardLayout.chartRef("Mira ![[charts/a.chart]]") == nil)
    }
    
    /// The problems the server tells Ari about, each at its line.
    @Test
    func problemsAreFound() throws {
        let text = """
        ---
        type: dashboard
        theme: {accent: blue, mode: dim}
        ---
        ::: columns
        ![[charts/ventas.chart]]
        ::: columns
        ![[charts/falta.chart]]
        """
        let layout = try #require(DashboardLayout.parse(text))
        
        #expect(layout.problems(chartPaths: Self.paths) == [
            .themeAccent("blue"), .themeMode("dim"), .nestedColumns(line: 6), .unclosedColumns(line: 4),
            .missingChart(ref: "charts/falta.chart", line: 7)
        ])
        
        let many = "---\ntype: dashboard\n---\n" + Array(repeating: "![[charts/ventas.chart]]", count: 25).joined(separator: "\n")
        #expect(try #require(DashboardLayout.parse(many)).problems(chartPaths: Self.paths) == [.tooManyCharts(25)])
    }
    
    /// "+ Chart" puts the exact embed line at the end, or before a line.
    @Test
    func aChartIsInserted() {
        let text = "---\ntype: dashboard\n---\n## Ventas\n\n"
        
        #expect(DashboardEdits.insertingChart("charts/ventas.chart", in: text) == "---\ntype: dashboard\n---\n## Ventas\n![[charts/ventas.chart]]\n")
        #expect(DashboardEdits.insertingChart("charts/a.chart", in: "a\nb", before: 1) == "a\n![[charts/a.chart]]\nb")
    }
    
    /// Removing takes a chart's line or a whole block; moving puts a block's lines before another's.
    @Test
    func blocksAreRemovedAndMoved() throws {
        let layout = try #require(DashboardLayout.parse(Self.example))
        let columns = layout.blocks[2].lines
        
        let removed = DashboardEdits.removing(6...6, from: Self.example)
        #expect(!removed.contains("ventas.chart"))
        #expect(try #require(DashboardLayout.parse(removed)).charts.count == 2)
        
        let moved = DashboardEdits.moving(block: columns, before: 5, in: Self.example)
        let lines = moved.components(separatedBy: "\n")
        #expect(Array(lines[5...11]) == ["::: columns", "![[charts/cobros.chart]]", "![[clientes.chart]]", ":::", "## Ventas",
                                         "![[charts/ventas.chart]]", "Text, lists and tables as in any note."])
        
        let toEnd = DashboardEdits.moving(block: 6...6, before: 12, in: Self.example)
        #expect(toEnd.hasSuffix("as in any note.\n![[charts/ventas.chart]]"))
        #expect(DashboardEdits.moving(block: 6...6, before: 7, in: Self.example) == Self.example)
    }
    
    /// The theme sheet writes one header line, replacing the one there (block style too), or removes it.
    @Test
    func theThemeIsWritten() throws {
        let theme = DashboardTheme(accent: "#112233", palette: ["#AABBCC"], mode: .dark)
        
        let replaced = DashboardEdits.settingTheme(theme, in: Self.example)
        #expect(replaced.contains("title: Octubre 2026\ntheme: {accent: \"#112233\", palette: [\"#AABBCC\"], mode: dark}\n---"))
        #expect(try #require(DashboardLayout.parse(replaced)).theme == theme)
        
        let block = "---\ntype: dashboard\ntheme:\n  accent: \"#22408A\"\n  mode: light\ntitle: A\n---\nText"
        let rewritten = DashboardEdits.settingTheme(theme, in: block)
        #expect(rewritten == "---\ntype: dashboard\ntheme: {accent: \"#112233\", palette: [\"#AABBCC\"], mode: dark}\ntitle: A\n---\nText")
        
        let added = DashboardEdits.settingTheme(DashboardTheme(mode: .auto), in: "---\ntype: dashboard\n---\n")
        #expect(added == "---\ntype: dashboard\ntheme: {mode: auto}\n---\n")
        
        #expect(DashboardEdits.settingTheme(DashboardTheme(), in: block) == "---\ntype: dashboard\ntitle: A\n---\nText")
    }
    
    /// A new dashboard's header, its title quoted when YAML would misread it.
    @Test
    func aNewDashboardIsWritten() throws {
        #expect(DashboardEdits.new(title: "Octubre") == "---\ntype: dashboard\ntitle: Octubre\n---\n")
        #expect(DashboardEdits.new(title: "2026") == "---\ntype: dashboard\ntitle: \"2026\"\n---\n")
        #expect(try #require(DashboardLayout.parse(DashboardEdits.new(title: "Ventas: octubre"))).title == "Ventas: octubre")
    }
}
