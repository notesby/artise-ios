//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Testing

struct NotesPushTests {
    /// The server's notes push names the chat; Sygnal's event ID beside it is ignored.
    @Test
    func notesPush() {
        let push: [AnyHashable: Any] = ["aps": ["content-available": 1], "artise_notes": ["room_id": "!abc:mas-k8s.artise.co"], "event_id": "$x"]
        #expect(NotesPush.roomID(from: push) == "!abc:mas-k8s.artise.co")
    }
    
    /// Message notifications and anything malformed aren't notes pushes.
    @Test
    func otherPushes() {
        #expect(NotesPush.roomID(from: ["aps": ["mutable-content": 1], "event_id": "$x", "room_id": "!abc:x"]) == nil)
        #expect(NotesPush.roomID(from: ["artise_notes": ["room_id": "abc"]]) == nil)
        #expect(NotesPush.roomID(from: ["artise_notes": "!abc:x"]) == nil)
    }
}
