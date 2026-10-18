//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

struct LocalNotesSearchTests {
    let files: [LocalFile] = [
        Self.note("Recetas/Tamales.md", "Masa de maíz\n\nHojas de maíz remojadas\nRelleno de pollo"),
        Self.note("Súper.md", "- leche\n- MAÍZ pozolero"),
        Self.note("Maíz.md", "Notas varias"),
        LocalFile(path: "attachments/maiz.jpg", version: "v", size: 1, modified: 0, isNote: false, content: nil, hasLocalEdits: false)
    ]
    
    /// Every word must match, ignoring case and accents; names first, then by path; only notes, never photos.
    @Test
    func matchesWordsInNamesAndLines() {
        let results = LocalNotesSearch.search(files, query: "maiz")
        #expect(results.map(\.path) == ["Maíz.md", "Recetas/Tamales.md", "Súper.md"])
        #expect(results[1].lines == ["Masa de maíz", "Hojas de maíz remojadas"])
        #expect(results[2].lines == ["- MAÍZ pozolero"])
        #expect(LocalNotesSearch.search(files, query: "maíz pollo").isEmpty)
        #expect(LocalNotesSearch.search(files, query: "relleno POLLO").map(\.path) == ["Recetas/Tamales.md"])
    }
    
    /// An empty query finds nothing; at most three lines per note and fifty notes.
    @Test
    func limits() {
        #expect(LocalNotesSearch.search(files, query: "   ").isEmpty)
        let long = Self.note("Larga.md", (1...10).map { "línea \($0) con sal" }.joined(separator: "\n"))
        #expect(LocalNotesSearch.search([long], query: "sal").first?.lines.count == 3)
        let many = (1...60).map { Self.note("n\($0).md", "sal") }
        #expect(LocalNotesSearch.search(many, query: "sal").count == 50)
    }
    
    private static func note(_ path: String, _ content: String) -> LocalFile {
        LocalFile(path: path, version: "v", size: 1, modified: 0, isNote: true, content: content, hasLocalEdits: false)
    }
}
