//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

/// Charts and dashboards from the Notes API: what the tree says each file is, pictures that are always asked again,
/// the chart and dashboard routes, exports, record types and unsaved charts.
struct NotesChartsTests {
    let room = FakeNotesServer.roomID
    let server = FakeNotesServer()
    let directory = makeTemporaryDirectory()
    
    func makeEngine() -> NotesSyncEngine {
        let tokens = CountingTokenProvider()
        let api = NotesAPIClient(transport: server, tokenSource: OpenIDNotesTokenSource { await tokens.next() })
        return NotesSyncEngine(api: api, directory: directory.appendingPathComponent("store"), cipher: ReversingCipher(),
                               files: NotesFileOptions(directory: directory.appendingPathComponent("files")))
    }
    
    // MARK: - The tree
    
    /// A `.md` the tree calls a dashboard lists as one, with its title; a business report is read-only; `.chart` is a note.
    @Test
    func theTreeSaysWhatEachFileIs() async throws {
        server.put("dashboards/Octubre.md", "---\ntype: dashboard\n---\n")
        server.describe("dashboards/Octubre.md", kind: "dashboard", title: "Octubre 2026")
        server.put("business/reports/2026-10.md", "---\ntype: report\n---\n")
        server.describe("business/reports/2026-10.md", kind: "dashboard", readonly: true)
        server.put("charts/ventas.chart", "title: Ventas\n")
        server.describe("charts/ventas.chart", kind: "chart", title: "Ventas")
        server.put("Súper.md", "leche")
        let engine = makeEngine()
        
        try await engine.sync(roomID: room)
        
        let dashboard = try #require(try await engine.file(roomID: room, path: "dashboards/Octubre.md"))
        #expect(dashboard.kind == .dashboard)
        #expect(dashboard.title == "Octubre 2026")
        #expect(!dashboard.isReadOnly)
        let report = try #require(try await engine.file(roomID: room, path: "business/reports/2026-10.md"))
        #expect(report.kind == .dashboard)
        #expect(report.isReadOnly)
        let chart = try #require(try await engine.file(roomID: room, path: "charts/ventas.chart"))
        #expect(chart.kind == .chart)
        #expect(chart.isNote)
        #expect(chart.content == "title: Ventas\n")
        #expect(try await engine.file(roomID: room, path: "Súper.md")?.kind == .note)
    }
    
    /// A file whose kind changes without a new version (a note turned dashboard by its header elsewhere) is updated.
    @Test
    func aKindIsUpdatedWithoutANewVersion() async throws {
        server.put("Plan.md", "x")
        server.put("Otro.md", "y")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        #expect(try await engine.file(roomID: room, path: "Plan.md")?.kind == .note)
        
        server.describe("Plan.md", kind: "dashboard", title: "Plan")
        server.put("Otro.md", "y2")
        try await engine.sync(roomID: room)
        
        #expect(try await engine.file(roomID: room, path: "Plan.md")?.kind == .dashboard)
        #expect(try await engine.file(roomID: room, path: "Plan.md")?.title == "Plan")
    }
    
    /// A phone that synced before the tree had kinds asks for the whole tree once, without its ETag: an unchanged chat
    /// would answer `304` and the kinds would never come.
    @Test
    func aPhoneFromBeforeKindsAsksForTheWholeTreeOnce() async throws {
        server.put("charts/ventas.chart", "title: Ventas\n")
        server.describe("charts/ventas.chart", kind: "chart")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        // As an older app left it: an ETag, and no tree fields.
        try await engine.store.updateChat(room) { record in
            record.treeFields = nil
            record.files["charts/ventas.chart"]?.kind = nil
        }
        
        try await engine.sync(roomID: room)
        try await engine.sync(roomID: room)
        
        let trees = server.requests(to: "tree")
        #expect(trees.count == 3)
        #expect(trees[1].headers["If-None-Match"] == nil)
        #expect(trees[2].headers["If-None-Match"] != nil)
        #expect(try await engine.file(roomID: room, path: "charts/ventas.chart")?.kind == .chart)
    }
    
    /// Ari's cards say what each document is; a `.md` card of kind dashboard opens as one.
    @Test
    func cardsTakeTheServersKind() {
        let json = #"{"content": {"co.artise.documents": [{"path": "Octubre.md", "kind": "dashboard"}, {"path": "charts/a.chart"}, {"path": "b.tsv"}]}}"#
        
        let cards = DocumentCards.read(originalJSON: json, latestEditJSON: nil)
        
        #expect(cards.map(\.kind) == [.dashboard, .chart, .table])
    }
    
    // MARK: - Pictures
    
    /// A chart's picture is asked for every time, with the last one's ETag: a `304` keeps it, a new one replaces it.
    @Test
    func aChartsPictureIsAlwaysAskedAgain() async throws {
        server.put("charts/ventas.chart", "title: Ventas\n")
        server.setDrawing("charts/ventas.chart", mode: "light", png: Data("v1".utf8), etag: "\"d1\"")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        let first = try #require(try await engine.drawing(roomID: room, path: "charts/ventas.chart", size: 512, mode: .light))
        let again = try #require(try await engine.drawing(roomID: room, path: "charts/ventas.chart", size: 512, mode: .light))
        server.setDrawing("charts/ventas.chart", mode: "light", png: Data("v2".utf8), etag: "\"d2\"")
        let changed = try #require(try await engine.drawing(roomID: room, path: "charts/ventas.chart", size: 512, mode: .light))
        
        let requests = server.requests(to: "preview")
        #expect(requests.count == 3)
        #expect(requests[0].headers["If-None-Match"] == nil)
        #expect(requests[0].query["mode"] == "light")
        #expect(requests[1].headers["If-None-Match"] == "\"d1\"")
        #expect(first == again)
        #expect(try Data(contentsOf: changed) == Data("v2".utf8))
        #expect(await engine.cachedDrawing(roomID: room, path: "charts/ventas.chart", size: 512, mode: .light) == changed)
    }
    
    /// Light and dark are kept apart; a chart the server can't draw has no picture.
    @Test
    func lightAndDarkAreKeptApart() async throws {
        server.put("charts/ventas.chart", "title: Ventas\n")
        server.put("charts/rota.chart", "title: Rota\n")
        server.setDrawing("charts/ventas.chart", mode: "light", png: Data("light".utf8), etag: "\"l\"")
        server.setDrawing("charts/ventas.chart", mode: "dark", png: Data("dark".utf8), etag: "\"d\"")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        let light = try #require(try await engine.drawing(roomID: room, path: "charts/ventas.chart", size: 256, mode: .light))
        let dark = try #require(try await engine.drawing(roomID: room, path: "charts/ventas.chart", size: 256, mode: .dark))
        
        #expect(try Data(contentsOf: light) == Data("light".utf8))
        #expect(try Data(contentsOf: dark) == Data("dark".utf8))
        #expect(await engine.cachedDrawing(roomID: room, path: "charts/ventas.chart", size: 512, mode: .light) == nil)
        #expect(try await engine.drawing(roomID: room, path: "charts/rota.chart", size: 256, mode: .light) == nil)
    }
    
    // MARK: - Routes
    
    /// `/chart` is asked with the mode and read whole; another file is `.noChart`, a busy server `.unavailable`.
    @Test
    func aChartIsRead() async throws {
        server.put("charts/ventas.chart", "title: Ventas\n")
        server.put("Súper.md", "leche")
        server.setChart("charts/ventas.chart", [
            "path": "charts/ventas.chart", "version": "v1", "as_of": "2026-10-23", "svg": "<svg/>",
            "spec": ["title": "Ventas", "type": "bar", "columns": ["Mes", "Ventas"], "rows": [["2026-05", 12000], ["2026-06", NSNull()]],
                     "series": ["Ventas"], "unit": "MXN", "caption": "Sin IVA", "colors": [], "compare": ""]
        ])
        let engine = makeEngine()
        
        let chart = try await engine.chart(roomID: room, path: "charts/ventas.chart", mode: .dark)
        
        #expect(server.requests(to: "chart").first?.query == ["path": "charts/ventas.chart", "mode": "dark"])
        #expect(chart.title == "Ventas")
        #expect(chart.rows == [[.text("2026-05"), .number(12000)], [.text("2026-06"), .text("")]])
        #expect(chart.asOf == "2026-10-23")
        #expect(chart.accessibilityText == "Ventas. Sin IVA")
        await #expect(throws: NotesError.noChart("That file isn't a chart.")) { try await engine.chart(roomID: room, path: "Súper.md", mode: .light) }
        server.put("charts/b.chart", "title: B\n")
        await #expect(throws: NotesError.unavailable("Can't draw now")) { try await engine.chart(roomID: room, path: "charts/b.chart", mode: .light) }
    }
    
    /// A dashboard's page comes as HTML; a note that isn't one is `.noDashboard`.
    @Test
    func aDashboardIsRead() async throws {
        server.put("Octubre.md", "---\ntype: dashboard\n---\n")
        server.put("Súper.md", "leche")
        server.setDashboard("Octubre.md", html: "<html>Octubre</html>")
        let engine = makeEngine()
        
        #expect(try await engine.dashboard(roomID: room, path: "Octubre.md") == "<html>Octubre</html>")
        #expect(server.requests(to: "dashboard").first?.headers["Authorization"] == "Bearer token-1")
        await #expect(throws: NotesError.self) { try await engine.dashboard(roomID: room, path: "Súper.md") }
    }
    
    /// An export is asked for with its format, and lands as a file named as the server names it.
    @Test
    func anExportIsANamedFile() async throws {
        server.put("charts/ventas.chart", "title: Ventas\n")
        server.setExport("charts/ventas.chart", format: "png", data: Data("png".utf8), name: "ventas por mes.png")
        let engine = makeEngine()
        
        let url = try await engine.export(roomID: room, path: "charts/ventas.chart", format: .png)
        
        #expect(url.lastPathComponent == "ventas por mes.png")
        #expect(try Data(contentsOf: url) == Data("png".utf8))
        #expect(server.requests(to: "export").first?.query == ["path": "charts/ventas.chart", "format": "png", "size": "1024"])
        await #expect(throws: NotesError.noExport("Can't be that format")) {
            try await engine.export(roomID: room, path: "charts/ventas.chart", format: .pdf)
        }
        #expect(NotesAPIClient.fileName(contentDisposition: #"attachment; filename="Octubre.pdf""#) == "Octubre.pdf")
    }
    
    /// The chat's record types, empty fields read as none.
    @Test
    func recordTypesAreRead() async throws {
        server.setRecordTypes([["type": "payment", "fields": ["date", "amount", "method"], "date_field": "date", "amount_field": "amount"],
                               ["type": "job", "fields": ["title"], "date_field": "", "amount_field": ""]])
        let engine = makeEngine()
        
        let types = try await engine.recordTypes(roomID: room)
        
        #expect(types == [NotesRecordType(type: "payment", fields: ["date", "amount", "method"], dateField: "date", amountField: "amount"),
                          NotesRecordType(type: "job", fields: ["title"], dateField: nil, amountField: nil)])
    }
    
    /// An unsaved chart is drawn from its text, at most 512 px; one the server can't draw says why.
    @Test
    func anUnsavedChartIsDrawn() async throws {
        let engine = makeEngine()
        
        let png = try await engine.chartPreview(roomID: room, content: "title: A\n", size: 1024, mode: .dark)
        
        let request = try #require(server.requests(to: "preview", method: "POST").first)
        #expect(request.path.hasSuffix("/chart/preview"))
        #expect(request.query == ["size": "512", "mode": "dark"])
        #expect(request.json?["content"] as? String == "title: A\n")
        #expect(png == Data("drawn:dark".utf8))
        await #expect(throws: NotesError.badChart("the chart needs a title")) {
            try await engine.chartPreview(roomID: room, content: "type: bar\n", size: 256, mode: .light)
        }
    }
    
    /// A chart the server refuses to save waits for the person with the server's sentence, and holds nothing else up.
    @Test
    func aRefusedChartWaitsWithTheServersSentence() async throws {
        server.put("charts/ventas.chart", "title: Ventas\n")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        try await engine.editNote(roomID: room, path: "charts/ventas.chart", content: "title: Ventas\ntype: radar\n")
        try await engine.createNote(roomID: room, path: "Otra.md", content: "hola")
        server.failNext("note", status: 422, error: "bad_chart")
        
        try await engine.sync(roomID: room)
        
        let edits = try await engine.edits(roomID: room)
        #expect(edits.count == 1)
        #expect(edits.first?.state == .rejected)
        #expect(edits.first?.error == "Failed on purpose")
        #expect(server.content("Otra.md") == "hola")
    }
}
