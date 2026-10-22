//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The extra keys Ari puts in a message's content for the apps (family-wiki's docs/notes-api.md, "Message fields
/// the apps read"): the reactions a message waits for, the kind of proposal it is, and the notes path of a file it
/// posted. Everyone else's messages, and Ari's ordinary answers, have none: their 👍/👎 is a rating, not an ask.
nonisolated struct ArtiseMessageFields: Hashable {
    static let reactionsKey = "co.artise.reactions"
    static let proposalKey = "co.artise.proposal"
    static let noteKey = "co.artise.note"
    
    /// The emojis the message accepts, in the order to show them: exactly the keys Ari answers to.
    var reactions: [String] = []
    /// The proposal's kind (`inbox_reply`, `invoice`, `booking`…) when the message is one. Any value counts: the
    /// list grows on the server without the app changing.
    var proposal: String?
    /// The file's path in the chat's notes, when Ari posted the notes' own copy of a document or photo.
    var notePath: String?
    
    var isProposal: Bool {
        proposal != nil
    }
    
    /// Reads the fields from the (decrypted) event's JSON; `nil` when it has none of them or can't be read.
    /// A malformed value (reactions that aren't a list of strings, a path that isn't text) is left out, never a crash.
    static func read(eventJSON: String?) -> ArtiseMessageFields? {
        guard let eventJSON, eventJSON.contains("co.artise."),
              let data = eventJSON.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let content = event["content"] as? [String: Any] ?? event
        var fields = ArtiseMessageFields()
        if let list = content[reactionsKey] as? [Any], let keys = list as? [String] {
            fields.reactions = keys.filter { !$0.isEmpty }
        }
        if let proposal = content[proposalKey] as? String, !proposal.isEmpty {
            fields.proposal = proposal
        }
        if let path = content[noteKey] as? String, !path.isEmpty {
            fields.notePath = path
        }
        return fields.reactions.isEmpty && fields.proposal == nil && fields.notePath == nil ? nil : fields
    }
    
    /// The emoji without the variation selector, so `✔` and `✔️` count as one.
    static func plainEmoji(_ key: String) -> String {
        key.replacingOccurrences(of: "\u{FE0F}", with: "")
    }
}

/// What the quick-reaction bar says for the reactions Ari asks for: on a proposal, ✅ is "Approve" and ❌ "Decline".
enum ArtiseReactionLabels {
    static func label(for key: String, fields: ArtiseMessageFields?) -> String? {
        guard let fields, fields.isProposal else { return nil }
        switch ArtiseMessageFields.plainEmoji(key) {
        case "✅": return ArtiseWorkspacesL10n.text("timeline_reaction_approve")
        case "❌": return ArtiseWorkspacesL10n.text("timeline_reaction_decline")
        default: return nil
        }
    }
}
