//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

/// Find in a note as it reads, and in a table's text.
struct NoteReadingFindTests {
    /// Matches across headings, paragraphs, list items, table rows and code are counted top to bottom, on the words
    /// people see rather than the Markdown marks.
    @Test
    func matchesAcrossBlocksInReadingOrder() {
        let document = NoteDocument(markdown: """
        ---
        type: receta
        aliases: [Mole de olla]
        ---
        # Mole **rojo**
        
        El mole lleva chile.
        
        - Chiles *guajillo* para el mole
        - [ ] Comprar mole
        
        | Ingrediente | Mole |
        |---|---|
        | chile | sí |
        
        ```
        mole()
        ```
        """)
        
        let matches = NoteReadingFind.matches(for: "mole", in: document.blocks)
        
        #expect(matches.map(\.slot) == [[0], [1, 0], [2, 0, 0, 0], [2, 1, 0, 0], [3, 0], [4]])
        #expect(matches.allSatisfy { $0.occurrence == 0 })
        // "Mole rojo": no asterisks in what's searched.
        #expect(NoteReadingFind.slots(in: document.blocks).first?.text == "Mole rojo")
        // The front-matter header isn't searched.
        #expect(NoteReadingFind.matches(for: "olla", in: document.blocks).isEmpty)
    }
    
    /// Case and accents don't matter, and the cursor wraps around.
    @Test
    func accentsDontMatterAndTheCursorWraps() {
        let document = NoteDocument(markdown: "Camión al mercado.\n\nEl CAMION llega tarde; otro camion.")
        
        let matches = NoteReadingFind.matches(for: "camion", in: document.blocks)
        
        #expect(matches.count == 3)
        #expect(matches[1] == NoteReadingMatch(slot: [1, 0], occurrence: 0, range: 3..<9))
        #expect(matches[2].occurrence == 1)
        var cursor = SearchCursor(count: matches.count)
        cursor.previous()
        #expect(cursor.position == 3)
        cursor.next()
        #expect(cursor.position == 1)
    }
    
    /// A table row is searched as the reading view draws it: the cells joined with " · ".
    @Test
    func tableRowsReadAsTheyAreDrawn() {
        let document = NoteDocument(markdown: "| a | b |\n|---|---|\n| uno | dos |")
        
        #expect(NoteReadingFind.slots(in: document.blocks).map(\.text) == ["a  ·  b", "uno  ·  dos"])
    }
    
    /// A CSV is read as lines, searched on the phone, and cut when it's huge.
    @Test
    func tableTextIsSearchedLineByLine() {
        let table = TableText(data: Data("\u{FEFF}producto,precio\r\nCafé,30\r\npan,5\r\ncafe molido,80".utf8))
        
        #expect(table.lines == ["producto,precio", "Café,30", "pan,5", "cafe molido,80"])
        #expect(table.isCut == false)
        #expect(table.matches(for: "CAFE") == [TableMatch(line: 1, occurrence: 0, range: 0..<4), TableMatch(line: 3, occurrence: 0, range: 0..<4)])
        
        let big = TableText(data: Data(String(repeating: "a,b\n", count: 10).utf8), limit: 10)
        #expect(big.isCut)
        #expect(big.lines.joined(separator: "\n").count == 10)
    }
}
