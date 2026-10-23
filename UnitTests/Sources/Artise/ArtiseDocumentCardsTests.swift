//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ElementX
import Foundation
import SwiftUI
import Testing

/// Document cards under Ari's messages, and find in a CSV and in a note as it reads.
@MainActor
struct ArtiseDocumentCardsTests {
    /// A reply about two documents carries two cards; nothing else needs to be on the message.
    @Test
    func aReplyCarriesItsDocuments() throws {
        let json = #"{"content":{"msgtype":"m.text","body":"Listo","co.artise.documents":[{"path":"Contratos/Ana.md","change":"created","draft":true},{"path":"Ventas.xlsx"}]}}"#
        
        let fields = try #require(ArtiseMessageFields.read(eventJSON: json))
        
        #expect(fields.documents.map(\.path) == ["Contratos/Ana.md", "Ventas.xlsx"])
        #expect(fields.documents.first?.isDraft == true)
        #expect(fields.reactions.isEmpty)
        #expect(!fields.isProposal)
    }
    
    /// Ari edits its progress message into the reply: the documents come from the latest edit.
    @Test
    func theLatestEditsDocumentsWin() throws {
        let original = #"{"content":{"msgtype":"m.notice","body":"Pensando…","co.artise.reactions":["✅"]}}"#
        let edit = #"{"content":{"body":"* Listo","m.new_content":{"body":"Listo","co.artise.documents":[{"path":"nuevo.md"}]}}}"#
        
        let fields = try #require(ArtiseMessageFields.read(eventJSON: original, latestEditJSON: edit))
        
        #expect(fields.documents.map(\.path) == ["nuevo.md"])
        #expect(fields.reactions == ["✅"])
        #expect(ArtiseMessageFields.read(eventJSON: #"{"content":{"body":"hola"}}"#, latestEditJSON: nil) == nil)
    }
    
    /// A CSV is searched on the phone: matches line by line, accents and case ignored, wrapping around.
    @Test
    func aTableIsSearchedOnThePhone() {
        var find = NoteTableFind()
        find.search("cafe", in: .init(data: Data("producto,precio\nCafé,30\npan,5\nCAFE molido,80".utf8)))
        
        #expect(find.status == .found(position: 1, total: 2))
        #expect(find.current?.line == 1)
        #expect(find.ranges(onLine: 3) == [0..<4])
        find.next()
        #expect(find.current?.line == 3)
        find.next()
        #expect(find.status == .found(position: 1, total: 2))
        find.search("té", in: .init(data: Data("a,b".utf8)))
        #expect(find.status == .none)
        find.search("  ", in: .init(data: Data("a,b".utf8)))
        #expect(find.status == .idle)
    }
    
    /// Matches are marked in place, the current one stronger; the words themselves don't change.
    @Test
    func matchesAreMarkedInPlace() {
        let text = AttributedString("Mole rojo y mole verde")
        
        let marked = NoteFindHighlight.apply(to: text, ranges: [0..<4, 12..<16], current: 12..<16)
        
        #expect(String(marked.characters) == "Mole rojo y mole verde")
        let colored = marked.runs.filter { $0.backgroundColor != nil }
        #expect(colored.count == 2)
        #expect(Set(colored.map { String(marked[$0.range].characters).lowercased() }) == ["mole"])
        #expect(NoteFindHighlight.apply(to: text, ranges: [], current: nil) == text)
    }
    
    /// The card's words in the three languages.
    @Test
    func theCardsWordsInTheThreeLanguages() {
        #expect(ArtiseNotesL10n.text("screen_notes_card_draft", language: "en") == "Draft")
        #expect(ArtiseNotesL10n.text("screen_notes_card_draft", language: "es") == "Borrador")
        #expect(ArtiseNotesL10n.text("screen_notes_card_draft", language: "pt") == "Rascunho")
        #expect(ArtiseNotesL10n.text("screen_notes_card_created", language: "es") == "Documento nuevo")
        #expect(ArtiseNotesL10n.text("screen_notes_card_changed", language: "pt") == "Atualizado")
        #expect(String(format: ArtiseNotesL10n.text("a11y_notes_card_open", language: "en"), "Contrato Ana") == "Open Contrato Ana")
        #expect(ArtiseNotesL10n.text("screen_notes_office_hint", language: "es").contains("Abrir con"))
    }
}
