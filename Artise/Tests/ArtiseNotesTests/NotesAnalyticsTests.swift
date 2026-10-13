//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Synchronization
import Testing

struct NotesAnalyticsTests {
    /// Events are named as on Android and carry only the kind of file or choice, never names or text.
    @Test
    func eventsAreNamedLikeAndroid() {
        #expect(NotesAnalyticsEvent(.noteSaved).name == "NotesNoteSaved")
        #expect(NotesAnalyticsEvent(.attachmentAdded, kind: "photo").properties == ["kind": "photo"])
        #expect(NotesAnalyticsEvent(.noteDeleted).properties.isEmpty)
    }
    
    /// The engine reports what was done: a new note, a save, an attachment and its kind.
    @Test
    func theEngineReportsActions() async throws {
        let seen = EventLog()
        let server = FakeNotesServer()
        let tokens = CountingTokenProvider()
        let api = NotesAPIClient(transport: server, tokenSource: OpenIDNotesTokenSource { await tokens.next() })
        let engine = NotesSyncEngine(api: api, directory: makeTemporaryDirectory(), cipher: ReversingCipher(),
                                     track: { event in seen.append(event.name + (event.kind.map { ":" + $0 } ?? "")) })
        
        try await engine.createNote(roomID: FakeNotesServer.roomID, path: "a.md", content: "x")
        try await engine.editNote(roomID: FakeNotesServer.roomID, path: "a.md", content: "y")
        _ = try await engine.addAttachment(roomID: FakeNotesServer.roomID, fileName: "f.pdf", data: Data(), contentType: "application/pdf")
        
        #expect(seen.entries == ["NotesNoteCreated", "NotesNoteSaved", "NotesAttachmentAdded:document"])
    }
}

/// Events seen by a test, from any thread.
final class EventLog: Sendable {
    private let storage = Mutex<[String]>([])
    
    var entries: [String] {
        storage.withLock { $0 }
    }
    
    func append(_ entry: String) {
        storage.withLock { $0.append(entry) }
    }
}
