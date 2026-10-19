//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

struct NotesMapTests {
    func note(_ path: String, _ content: String) -> LocalFile {
        LocalFile(path: path, version: "v", size: 1, modified: 0, isNote: true, content: content, hasLocalEdits: false)
    }
    
    /// Links in either direction are one edge; photos and missing notes aren't on the map.
    @Test
    func linksBecomeEdgesOnce() {
        let files = [note("Súper.md", "Ver [[Mole]] y ![[luna.jpg]] y [[Nada]]"), note("Recetas/Mole.md", "Volver a [[Súper]]"),
                     note("Ideas.md", "sin enlaces"),
                     LocalFile(path: "luna.jpg", version: "v", size: 1, modified: 0, isNote: false, content: nil, hasLocalEdits: false)]
        
        let map = NotesMapBuilder.build(files)
        
        #expect(map.nodes.map(\.path) == ["Ideas.md", "Recetas/Mole.md", "Súper.md"])
        #expect(map.edges == [MapEdge(from: 1, to: 2)])
        #expect(map.nodes.map(\.degree) == [0, 1, 1])
        #expect(map.nodes.map(\.name) == ["Ideas", "Mole", "Súper"])
    }
    
    /// Pages are marked and named by their title; links by alias join them; a name two notes share joins nothing.
    @Test
    func pagesAreMarkedAndAliasesJoin() {
        let files = [note("people/Ana.md", "---\ntype: person\naliases: [Mamá]\n---\nVive en Monterrey"),
                     note("clients/Ana.md", "Compra pasteles"),
                     note("Diario.md", "Comí con [[Mamá]] y vi a [[Ana]]")]
        let pages = [NotesPage(path: "people/Ana.md", title: "Ana", type: "person", folder: "people", aliases: ["Mamá"], summary: "", isNote: true),
                     NotesPage(path: "clients/Ana.md", title: "Ana", type: "client", folder: "clients", aliases: [], summary: "", isNote: true)]
        
        let map = NotesMapBuilder.build(files, pages: pages)
        
        #expect(map.nodes.map(\.path) == ["clients/Ana.md", "Diario.md", "people/Ana.md"])
        #expect(map.nodes.map(\.isPage) == [true, false, true])
        #expect(map.edges == [MapEdge(from: 1, to: 2)])
    }
    
    /// Relative Markdown links to notes count; headings don't make a different note.
    @Test
    func markdownLinksAndHeadingsCount() {
        #expect(NotesMapBuilder.linkTargets("[lista](Listas/S%C3%BAper.md) y [[Mole#Salsa]]") == ["Listas/Súper.md", "Mole"])
    }
    
    /// The same notes always give the same map, inside the margins.
    @Test
    func layoutIsStableAndInside() {
        let files = (0..<12).map { note("n\($0).md", "[[n\(($0 + 1) % 12)]]") }
        
        let first = NotesMapBuilder.build(files)
        let second = NotesMapBuilder.build(files)
        
        #expect(first == second)
        #expect(first.nodes.allSatisfy { (0.11...0.89).contains($0.x) && (0.11...0.89).contains($0.y) })
    }
    
    /// Zooming keeps the point between the fingers where it is, and stays within the limits.
    @Test
    func zoomKeepsTheFocusInPlace() {
        let viewport = MapViewport.reset.zoomed(by: 2, focusX: 300, focusY: 100, centerX: 200, centerY: 200)
        let focus = viewport.toScreen(x: 300, y: 100, centerX: 200, centerY: 200)
        
        #expect(abs(focus.x - 300) < 0.0001)
        #expect(abs(focus.y - 100) < 0.0001)
        #expect(MapViewport.reset.zoomed(by: 100, focusX: 0, focusY: 0, centerX: 0, centerY: 0).scale == MapViewport.maxScale)
        #expect(!viewport.isReset)
    }
}
