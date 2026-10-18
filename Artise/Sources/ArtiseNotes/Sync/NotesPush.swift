//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

/// The silent push the server sends when a chat's notes change, to wake the app and update that chat:
/// `{"aps":{"content-available":1},"artise_notes":{"room_id":"!…"},"event_id":"$…"}`. It carries no names or text.
public enum NotesPush {
    /// The chat whose notes changed, or `nil` when the push is something else.
    public static func roomID(from userInfo: [AnyHashable: Any]) -> String? {
        guard let notes = userInfo["artise_notes"] as? [String: Any],
              let roomID = notes["room_id"] as? String, roomID.hasPrefix("!") else { return nil }
        return roomID
    }
}
