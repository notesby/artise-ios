//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ElementX
import Foundation
import Testing

struct ArtiseNotesServiceTests {
    /// The bot's state event carries the tree hash; anything else means "no live updates here".
    @Test
    func treeHashIsReadFromTheStateEvent() {
        #expect(NotesTreeListener.tree(from: #"{"tree": "9f1c"}"#) == "9f1c")
        #expect(NotesTreeListener.tree(from: #"{"tree": ""}"#) == nil)
        #expect(NotesTreeListener.tree(from: "{}") == nil)
        #expect(NotesTreeListener.tree(from: "not json") == nil)
    }
    
    /// Each account's notes live in their own folder, named safely from the user ID.
    @Test
    func accountsGetTheirOwnFolder() {
        let ana = ArtiseNotesService.directory(for: "@ana:artise.co")
        let luis = ArtiseNotesService.directory(for: "@luis:artise.co")
        
        #expect(ana != luis)
        #expect(!ana.lastPathComponent.contains("/"))
        #expect(ana.pathComponents.contains("ArtiseNotes"))
    }
}
