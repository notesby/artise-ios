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

struct RenameAndMoveTests {
    /// Renaming keeps a note a note and a file's extension when it's left out.
    @Test
    func renamedPaths() {
        #expect(NoteNames.renamedPath("Recetas/Mole.md", to: "Mole poblano") == "Recetas/Mole poblano.md")
        #expect(NoteNames.renamedPath("factura.pdf", to: "recibo") == "recibo.pdf")
        #expect(NoteNames.renamedPath("factura.pdf", to: "recibo.PDF") == "recibo.PDF")
    }
    
    /// Renaming to a name already used is refused; renaming to the same name in other case isn't.
    @Test
    func renameProblems() {
        #expect(NoteNames.renameProblem("Mole.md", to: "Súper", existingPaths: ["Mole.md", "Súper.md"]) == .exists)
        #expect(NoteNames.renameProblem("Mole.md", to: "mole", existingPaths: ["Mole.md"]) == nil)
        #expect(NoteNames.renameProblem("Mole.md", to: "a/b", existingPaths: []) == .invalid)
    }
    
    /// Moving keeps the name; folders are tidied and checked.
    @Test
    func movesAndFolders() {
        #expect(NoteNames.movedPath("Recetas/Mole.md", to: "") == "Mole.md")
        #expect(NoteNames.movedPath("Mole.md", to: "Cocina") == "Cocina/Mole.md")
        #expect(NoteNames.renamedFolder("Recetas/Postres", to: "Dulces") == "Recetas/Dulces")
        #expect(NoteNames.folderPath("  Recetas / Postres/ ") == "Recetas/Postres")
        #expect(NoteNames.folderProblem("Recetas//Postres") == .invalid)
        #expect(NoteNames.folderProblem(".trash") == .invalid)
        #expect(NoteNames.folderProblem("Recetas/Postres") == nil)
    }
    
    /// New charts go in `charts/`, new dashboards in `dashboards/`, numbered when the name is taken.
    @Test
    func newChartsAndDashboardsGetFreePaths() {
        #expect(NoteNames.newChartPath(named: " Ventas ", taken: []) == "charts/Ventas.chart")
        #expect(NoteNames.newChartPath(named: "Ventas", taken: ["charts/ventas.chart"]) == "charts/Ventas (2).chart")
        #expect(NoteNames.newChartPath(named: "a/b", taken: []) == nil)
        #expect(NoteNames.newDashboardPath(named: "Octubre", taken: ["dashboards/Octubre.md"]) == "dashboards/Octubre (2).md")
        #expect(NoteNames.newDashboardPath(named: "", taken: []) == nil)
    }
}
