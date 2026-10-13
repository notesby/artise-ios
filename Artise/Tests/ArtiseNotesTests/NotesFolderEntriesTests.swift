//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

struct NotesFolderEntriesTests {
    func file(_ path: String, isNote: Bool = true, edits: Bool = false) -> LocalFile {
        LocalFile(path: path, version: "v", size: 10, modified: 0, isNote: isNote, content: isNote ? "" : nil, hasLocalEdits: edits)
    }
    
    /// The top level lists folders (with what they hold), then notes, then photos and files, each by name.
    @Test
    func topLevelShowsFoldersThenNotesThenFiles() {
        let files = [file("Súper.md"), file("agenda.md", edits: true), file("Recetas/Mole.md"), file("Recetas/Postres/Flan.md"),
                     file("Recetas/flan.jpg", isNote: false), file("factura.pdf", isNote: false)]
        
        let entries = NotesFolderEntries.entries(files: files, folder: "", allFolders: ["Viajes"])
        
        #expect(entries == [.folder(name: "Recetas", path: "Recetas", notes: 2, files: 1),
                            .folder(name: "Viajes", path: "Viajes", notes: 0, files: 0),
                            .note(name: "agenda", path: "agenda.md", hasLocalEdits: true),
                            .note(name: "Súper", path: "Súper.md", hasLocalEdits: false),
                            .file(name: "factura.pdf", path: "factura.pdf", isImage: false, size: 10)])
    }
    
    /// Inside a folder, only what's directly in it shows, with deeper folders as rows.
    @Test
    func subfoldersShowTheirOwnContents() {
        let files = [file("Recetas/Mole.md"), file("Recetas/Postres/Flan.md"), file("Súper.md")]
        
        let entries = NotesFolderEntries.entries(files: files, folder: "Recetas", allFolders: ["Recetas/Vacía"])
        
        #expect(entries == [.folder(name: "Postres", path: "Recetas/Postres", notes: 1, files: 0),
                            .folder(name: "Vacía", path: "Recetas/Vacía", notes: 0, files: 0),
                            .note(name: "Mole", path: "Recetas/Mole.md", hasLocalEdits: false)])
    }
    
    /// Notes lose ".md"; other text files keep their extension; photos are recognised by extension.
    @Test
    func namesAndKinds() {
        #expect(NotesFolderEntries.noteName("Recetas/Mole.md") == "Mole")
        #expect(NotesFolderEntries.noteName("lista.csv") == "lista.csv")
        #expect(NotesFolderEntries.isImage("Fotos/luna.HEIC"))
        #expect(!NotesFolderEntries.isImage("factura.pdf"))
    }
}
