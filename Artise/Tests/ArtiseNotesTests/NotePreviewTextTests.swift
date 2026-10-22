//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

/// The first lines of a note, as a list shows them.
struct NotePreviewTextTests {
    @Test
    func theFirstLinesLoseTheirMarks() {
        let note = """
        ---
        type: recipe
        ---
        ## Mole poblano
        
        - [ ] comprar **chiles**
        - [[Ana|Mamá]] trae el chocolate
        """
        #expect(NotePreviewText.firstLines(of: note) == "Mole poblano · comprar chiles")
        #expect(NotePreviewText.firstLines(of: note, lines: 3) == "Mole poblano · comprar chiles · Mamá trae el chocolate")
    }
    
    @Test
    func emptyNotesHaveNoPreview() {
        #expect(NotePreviewText.firstLines(of: nil) == nil)
        #expect(NotePreviewText.firstLines(of: "") == nil)
        #expect(NotePreviewText.firstLines(of: "---\ntype: person\n---\n\n") == nil)
        #expect(NotePreviewText.firstLines(of: "---\n\n***") == nil)
    }
    
    @Test
    func linksAndEmbedsKeepTheirWords() {
        #expect(NotePreviewText.plain("> ![[foto.jpg]] de [la playa](https://x.y)") == "foto.jpg de la playa")
        #expect(NotePreviewText.plain("1. `code` ~~viejo~~ _nuevo_") == "code viejo nuevo")
        #expect(NotePreviewText.plain("- [x] hecho") == "hecho")
    }
    
    @Test
    func longLinesAreCut() {
        let long = String(repeating: "palabra ", count: 40)
        let preview = NotePreviewText.firstLines(of: long)
        #expect(preview?.hasSuffix("…") == true)
        #expect((preview?.count ?? 0) <= NotePreviewText.maxCharacters + 1)
    }
}
