//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

struct PageIndexTests {
    let ana = NotesPage(path: "people/Ana.md", title: "Ana", type: "person", folder: "people", aliases: ["Mamá", "Mother"],
                        summary: "Ana, Hector's mother", isNote: true)
    let client = NotesPage(path: "clients/Ana.md", title: "Ana", type: "client", folder: "clients", aliases: [], summary: "Buys cakes", isNote: true)
    let photo = NotesPage(path: "Fotos/playa.jpg", title: "playa.jpg", type: "image", folder: "Fotos", aliases: [], summary: "", isNote: false)
    
    /// A path, a name in any folder, a title and an alias all find the note; accents and case don't matter.
    @Test
    func linksResolveByPathNameTitleAndAlias() {
        let index = PageIndex(paths: ["people/Ana.md", "Súper.md", "Fotos/playa.jpg"], pages: [ana, photo])
        
        #expect(index.resolve("people/Ana") == .file("people/Ana.md"))
        #expect(index.resolve("Ana") == .file("people/Ana.md"))
        #expect(index.resolve("mama") == .file("people/Ana.md"))
        #expect(index.resolve("Mother") == .file("people/Ana.md"))
        #expect(index.resolve("super") == .file("Súper.md"))
        #expect(index.resolve("playa.jpg") == .file("Fotos/playa.jpg"))
        #expect(index.resolve("Papá") == .missing)
        #expect(index.resolve("") == .missing)
    }
    
    /// Two notes with one name make the link ambiguous, with the folder and summary to tell them apart; the path form picks one.
    @Test
    func sharedNamesAreAmbiguous() {
        let index = PageIndex(paths: ["people/Ana.md", "clients/Ana.md"], pages: [ana, client])
        
        let candidates = [LinkCandidate(path: "clients/Ana.md", title: "Ana", folder: "clients", summary: "Buys cakes", type: "client"),
                          LinkCandidate(path: "people/Ana.md", title: "Ana", folder: "people", summary: "Ana, Hector's mother", type: "person")]
        #expect(index.resolve("Ana") == .ambiguous(candidates))
        #expect(candidates.map(\.linkText) == ["clients/Ana|Ana", "people/Ana|Ana"])
        #expect(index.resolve("people/Ana") == .file("people/Ana.md"))
        // The alias belongs to one of them only.
        #expect(index.resolve("Mamá") == .file("people/Ana.md"))
    }
    
    /// Plain notes without pages share names too: the choice is offered rather than the shortest path opened.
    @Test
    func plainNotesWithOneNameAreAmbiguous() {
        let index = PageIndex(paths: ["Mole.md", "Recetas/Mole.md"], pages: [])
        
        #expect(index.resolve("Mole") == .ambiguous([LinkCandidate(path: "Mole.md", title: "Mole", folder: "", summary: "", type: ""),
                                                     LinkCandidate(path: "Recetas/Mole.md", title: "Mole", folder: "Recetas", summary: "", type: "")]))
    }
    
    /// A name typed by hand is written as Obsidian does: an alias becomes `[[Ana|Mamá]]`; a note's own name or a path stays.
    @Test
    func typedAliasesAreWrittenWithTheirPage() {
        let index = PageIndex(paths: ["people/Ana.md", "Súper.md"], pages: [ana])
        
        #expect(index.written("Mamá") == WrittenLink(target: "Ana", shownText: "Mamá"))
        #expect(index.written("mother") == WrittenLink(target: "Ana", shownText: "mother"))
        #expect(index.written("Ana") == nil)
        #expect(index.written("people/Ana") == nil)
        #expect(index.written("Súper") == nil)
        #expect(index.written("Nadie") == nil)
    }
    
    /// Pages are the notes in `(pages)` folders; their title names them on the map.
    @Test
    func pagesAreKnownByPath() {
        let index = PageIndex(paths: ["people/Ana.md", "Súper.md", "Fotos/playa.jpg"], pages: [ana, photo])
        
        #expect(index.isPage("people/Ana.md"))
        #expect(!index.isPage("Súper.md"))
        #expect(!index.isPage("Fotos/playa.jpg"))
        #expect(index.title(of: "people/Ana.md") == "Ana")
        #expect(index.title(of: "Súper.md") == "Súper")
    }
}
