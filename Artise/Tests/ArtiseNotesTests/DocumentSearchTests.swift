//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

/// Finding words in a document, the way people type them.
struct DocumentSearchTests {
    /// Case and accents don't matter: "camion" finds "camión" and "CAMIÓN".
    @Test
    func caseAndAccentsAreIgnored() {
        let text = "El camión salió. Otro CAMIÓN llegó; camion sin acento."
        
        let ranges = DocumentSearch.ranges(of: "camion", in: text)
        
        #expect(ranges.count == 3)
        #expect(ranges.map { (text as NSString).substring(with: NSRange($0)) } == ["camión", "CAMIÓN", "camion"])
        #expect(DocumentSearch.ranges(of: "Mole", in: "mole MOLE Mole").count == 3)
    }
    
    /// Nothing is found for nothing, and matches never overlap.
    @Test
    func emptyQueriesAndOverlaps() {
        #expect(DocumentSearch.ranges(of: "", in: "algo").isEmpty)
        #expect(DocumentSearch.ranges(of: "  ", in: "algo").isEmpty)
        #expect(DocumentSearch.ranges(of: "aa", in: "aaaa") == [0..<2, 2..<4])
        #expect(DocumentSearch.ranges(of: "x", in: "").isEmpty)
    }
    
    /// Across pages the matches come page by page, several on one page in order.
    @Test
    func matchesComeInPageOrder() {
        let pages = [NotesDocumentText.Page(number: 2, text: "chiles y chocolate"),
                     NotesDocumentText.Page(number: 1, text: "Mole poblano con chiles; más chiles")]
        
        let matches = DocumentSearch.matches(for: "chiles", in: pages)
        
        #expect(matches.map(\.page) == [1, 1, 2])
        #expect(matches[0].range == 17..<23)
        #expect(matches[1].range.lowerBound > matches[0].range.lowerBound)
        #expect(matches[2].range == 0..<6)
    }
    
    /// Next and previous wrap around, and the position is counted from 1.
    @Test
    func theCursorWrapsAround() {
        var cursor = SearchCursor(count: 3)
        #expect(cursor.position == 1)
        cursor.next()
        cursor.next()
        #expect(cursor.position == 3)
        cursor.next()
        #expect(cursor.position == 1)
        cursor.previous()
        #expect(cursor.position == 3)
        
        var empty = SearchCursor(count: 0)
        #expect(empty.position == nil)
        empty.next()
        #expect(empty.position == nil)
    }
    
    /// A snippet shows a few words around the match, with dots where the text goes on.
    @Test
    func snippetsShowTheWordsAround() {
        let text = "Primero se tuestan los chiles anchos y pasilla en el comal, sin quemarlos, y luego se remojan."
        let range = DocumentSearch.ranges(of: "comal", in: text)[0]
        
        let snippet = DocumentSearch.snippet(around: range, in: text, context: 10)
        
        #expect(snippet == "…lla en el comal, sin quem…")
        #expect(DocumentSearch.snippet(around: 0..<7, in: "Primero") == "Primero")
    }
    
    /// The editor searches the text it holds, unsaved edits included, and a match can be selected without an undo step.
    @Test
    func theEditorSearchesUnsavedText() {
        var model = NoteEditorModel(text: "Mole")
        model.viewChanged(text: "Mole con camión", selection: 15..<15, now: .now)
        
        let ranges = DocumentSearch.ranges(of: "camion", in: model.text)
        #expect(ranges == [9..<15])
        
        let stepsBefore = model.canUndo
        model.select(ranges[0])
        #expect(model.selection == 9..<15)
        #expect(model.canUndo == stepsBefore)
        #expect(model.text == "Mole con camión")
    }
}
