//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

/// The documents Ari's message is about (`co.artise.documents`), read as cards, and what each kind of file is.
struct DocumentCardsTests {
    private func event(_ documents: String) -> String {
        #"{"type":"m.room.message","content":{"msgtype":"m.text","body":"Listo","co.artise.documents":\#(documents)}}"#
    }
    
    /// A reply about two documents gives two cards with everything the server said.
    @Test
    func aReplyWithTwoDocuments() {
        let json = event(#"""
        [{"path":"Contratos/Contrato Ana.md","version":"3f2a","kind":"note","title":"Contrato Ana","change":"created","draft":true},
         {"path":"Ventas/Octubre.xlsx","change":"changed"}]
        """#)
        
        let cards = DocumentCards.read(originalJSON: json, latestEditJSON: nil)
        
        #expect(cards.count == 2)
        #expect(cards[0] == DocumentCard(path: "Contratos/Contrato Ana.md", version: "3f2a", title: "Contrato Ana", change: .created, isDraft: true))
        #expect(cards[0].kind == .note)
        #expect(cards[1].title == "Octubre.xlsx")
        #expect(cards[1].kind == .office)
        #expect(cards[1].change == .changed)
        #expect(cards[1].isDraft == false)
        #expect(cards[1].version == nil)
    }
    
    /// Ari edits its progress message into the reply: the edit's `m.new_content` is what counts.
    @Test
    func theLatestEditWins() {
        let original = event(#"[{"path":"viejo.md"}]"#)
        let edit = #"{"type":"m.room.message","content":{"body":"* Listo","m.new_content":{"body":"Listo","co.artise.documents":[{"path":"nuevo.md"}]}}}"#
        
        #expect(DocumentCards.read(originalJSON: original, latestEditJSON: edit).map(\.path) == ["nuevo.md"])
        // An edit without documents leaves the original's.
        let plainEdit = #"{"content":{"m.new_content":{"body":"Listo"}}}"#
        #expect(DocumentCards.read(originalJSON: original, latestEditJSON: plainEdit).map(\.path) == ["viejo.md"])
        // A progress message that only gets them in its edit.
        #expect(DocumentCards.read(originalJSON: #"{"content":{"body":"Pensando…"}}"#, latestEditJSON: edit).map(\.path) == ["nuevo.md"])
    }
    
    /// No path, a repeated path, junk values and more than four: what's usable is kept, the rest left out.
    @Test
    func oddEntriesAreLeftOut() {
        let json = event(#"""
        [{"title":"sin ruta"}, {"path":""}, "texto", 7, {"path":"a.md","change":"borrado","draft":"sí","version":5,"title":"  "},
         {"path":"a.md"}, {"path":"b.pdf"}, {"path":"c.csv"}, {"path":"d.jpg"}, {"path":"e.docx"}]
        """#)
        
        let cards = DocumentCards.read(originalJSON: json, latestEditJSON: nil)
        
        #expect(cards.map(\.path) == ["a.md", "b.pdf", "c.csv", "d.jpg"])
        #expect(cards[0] == DocumentCard(path: "a.md"))
        #expect(cards[0].title == "a")
        #expect(DocumentCards.read(originalJSON: event(#"{"path":"a.md"}"#), latestEditJSON: nil).isEmpty)
        #expect(DocumentCards.read(originalJSON: "not json co.artise.documents", latestEditJSON: nil).isEmpty)
        #expect(DocumentCards.read(originalJSON: nil, latestEditJSON: nil).isEmpty)
    }
    
    /// The kind comes from the extension, the same way opening is routed.
    @Test
    func kindsComeFromTheExtension() {
        #expect(NoteDocumentKind.of("Recetas/Mole.md") == .note)
        #expect(NoteDocumentKind.of("leeme.TXT") == .note)
        #expect(NoteDocumentKind.of("Factura.pdf") == .pdf)
        #expect(NoteDocumentKind.of("Fotos/luna.jpeg") == .image)
        #expect(NoteDocumentKind.of("lista.csv") == .table)
        for name in ["a.docx", "a.doc", "a.odt", "a.rtf", "a.xlsx", "a.xls", "a.ods", "a.pptx", "a.ppt", "a.odp"] {
            #expect(NoteDocumentKind.of(name) == .office, "\(name)")
        }
        #expect(NoteDocumentKind.of("audio.m4a") == .other)
        #expect(NoteDocumentKind.of("Makefile") == .other)
        #expect(NoteDocumentKind.of(".hidden") == .other)
    }
}
