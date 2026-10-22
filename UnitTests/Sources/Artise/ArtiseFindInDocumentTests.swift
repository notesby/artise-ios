//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
@testable import ElementX
import Foundation
import PDFKit
import Testing

/// Finding words in a PDF: PDFKit's own search, or the server's text when the document has no text layer.
@MainActor
struct ArtiseFindInDocumentTests {
    /// The counter reads "3 of 12" in English, "3 de 12" in Spanish and Portuguese, and "No matches" in each.
    @Test
    func theCounterInTheThreeLanguages() {
        #expect(String(format: ArtiseNotesL10n.text("screen_notes_find_count", language: "en"), 3, 12) == "3 of 12")
        #expect(String(format: ArtiseNotesL10n.text("screen_notes_find_count", language: "es"), 3, 12) == "3 de 12")
        #expect(String(format: ArtiseNotesL10n.text("screen_notes_find_count", language: "pt"), 3, 12) == "3 de 12")
        #expect(ArtiseNotesL10n.text("screen_notes_find_none", language: "en") == "No matches")
        #expect(ArtiseNotesL10n.text("screen_notes_find_none", language: "es") == "Sin resultados")
        #expect(ArtiseNotesL10n.text("screen_notes_find_none", language: "pt") == "Sem resultados")
        #expect(ArtiseNotesL10n.findCount(3, of: 12).contains("3"))
    }
    
    /// A document with words is searched by PDFKit: every match highlighted, next wraps around, no server call.
    @Test
    func aDocumentWithTextIsSearchedByPDFKit() async {
        let document = makeDocument(pages: ["El camión llegó.", "Otro camion, y un CAMIÓN más."])
        var asked = false
        let model = NotePDFSearchModel(document: document) {
            asked = true
            return NotesDocumentText(path: "a.pdf", version: "1", pages: [])
        }
        
        #expect(model.source == .pdfKit)
        model.search("camion")
        await model.waitForSearch()
        
        #expect(model.selections.count == 3)
        #expect(model.status == .found(position: 1, total: 3))
        #expect(model.currentSelection === model.selections[0])
        model.next()
        model.next()
        #expect(model.status == .found(position: 3, total: 3))
        model.next()
        #expect(model.status == .found(position: 1, total: 3))
        #expect(model.snippet == nil)
        #expect(!asked)
    }
    
    /// A document with no text layer (a scan) is searched with the server's text: it turns to the match's page and
    /// shows its words, the way the Android app does.
    @Test
    func aDocumentWithoutTextUsesTheServersText() async {
        let model = NotePDFSearchModel(document: makeBlankDocument(pages: 2)) {
            NotesDocumentText(path: "scan.pdf", version: "1", pages: [.init(number: 1, text: "Mole poblano"),
                                                                      .init(number: 2, text: "chiles y chiles")])
        }
        
        #expect(model.source == .serverText)
        model.search("chiles")
        await model.waitForSearch()
        
        #expect(model.status == .found(position: 1, total: 2))
        #expect(model.currentPage == 2)
        #expect(model.snippet == "chiles y chiles")
        #expect(model.selections.isEmpty)
        model.search("nada")
        await model.waitForSearch()
        #expect(model.status == .none)
    }
    
    /// When the server can't give the text (too big, no text), the field says search isn't available; no error.
    @Test
    func anUnavailableTextSaysSo() async {
        let model = NotePDFSearchModel(document: makeBlankDocument(pages: 1)) {
            throw NotesError.tooBig("Too big")
        }
        
        model.search("algo")
        await model.waitForSearch()
        
        #expect(model.status == .unavailable)
        #expect(model.currentPage == nil)
    }
    
    private func makeDocument(pages: [String]) -> PDFDocument {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for text in pages {
                context.beginPage()
                NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 14)]).draw(at: CGPoint(x: 20, y: 20))
            }
        }
        return PDFDocument(data: data) ?? PDFDocument()
    }
    
    private func makeBlankDocument(pages: Int) -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<pages {
            document.insert(PDFPage(), at: index)
        }
        return document
    }
}
