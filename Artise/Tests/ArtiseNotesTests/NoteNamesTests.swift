//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

struct NoteNamesTests {
    /// A typed name becomes a note in the folder, with ".md" added once.
    @Test
    func namesBecomePaths() {
        #expect(NoteNames.path(for: " Mole ", in: "Recetas") == "Recetas/Mole.md")
        #expect(NoteNames.path(for: "Súper.md", in: "") == "Súper.md")
    }
    
    /// Empty names, slashes and hidden names are refused; a name already used (any case) says so.
    @Test
    func problemsAreFound() {
        #expect(NoteNames.problem(with: "  ", in: "", existingPaths: []) == .invalid)
        #expect(NoteNames.problem(with: "a/b", in: "", existingPaths: []) == .invalid)
        #expect(NoteNames.problem(with: ".oculta", in: "", existingPaths: []) == .invalid)
        #expect(NoteNames.problem(with: "súper", in: "", existingPaths: ["Súper.md"]) == .exists)
        #expect(NoteNames.problem(with: "Mole", in: "Recetas", existingPaths: ["Mole.md"]) == nil)
    }
}

struct FreePathTests {
    /// Keeping both notes gives this phone's copy the next free name.
    @Test
    func takenNamesGetANumber() {
        #expect(NoteNames.freePath(for: "Ideas.md", taken: ["ideas.md"]) == "Ideas (2).md")
        #expect(NoteNames.freePath(for: "Ideas.md", taken: ["Ideas.md", "Ideas (2).md"]) == "Ideas (3).md")
        #expect(NoteNames.freePath(for: "Nueva.md", taken: ["Ideas.md"]) == "Nueva.md")
    }
}
