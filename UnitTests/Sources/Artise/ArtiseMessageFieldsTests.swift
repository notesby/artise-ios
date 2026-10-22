//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ElementX
import Foundation
import Testing

/// The fields Ari adds to its messages for the apps, read from the event's JSON.
struct ArtiseMessageFieldsTests {
    /// A proposal: the reactions it takes, in order, and its kind.
    @Test
    func reactionsAndProposalAreRead() throws {
        let fields = try #require(ArtiseMessageFields.read(eventJSON: event(#""co.artise.reactions": ["✅", "❌"], "co.artise.proposal": "inbox_reply""#)))
        #expect(fields.reactions == ["✅", "❌"])
        #expect(fields.proposal == "inbox_reply")
        #expect(fields.isProposal)
        #expect(fields.notePath == nil)
    }
    
    /// A reminder offers reactions without being a proposal.
    @Test
    func reactionsAloneAreNotAProposal() throws {
        let fields = try #require(ArtiseMessageFields.read(eventJSON: event(#""co.artise.reactions": ["⏰", "🔁"]"#)))
        #expect(fields.reactions == ["⏰", "🔁"])
        #expect(!fields.isProposal)
    }
    
    /// Everyone else's messages, Ari's answers and unreadable JSON have no fields.
    @Test
    func messagesWithoutTheKeysHaveNone() {
        #expect(ArtiseMessageFields.read(eventJSON: event(#""body": "hola""#)) == nil)
        #expect(ArtiseMessageFields.read(eventJSON: nil) == nil)
        #expect(ArtiseMessageFields.read(eventJSON: "co.artise.reactions but not json") == nil)
    }
    
    /// A list that isn't one, or holds something other than text, is ignored; the rest of the fields still count.
    @Test
    func malformedValuesAreIgnored() {
        #expect(ArtiseMessageFields.read(eventJSON: event(#""co.artise.reactions": "✅""#)) == nil)
        #expect(ArtiseMessageFields.read(eventJSON: event(#""co.artise.reactions": ["✅", 3]"#)) == nil)
        let proposalOnly = ArtiseMessageFields.read(eventJSON: event(#""co.artise.reactions": 7, "co.artise.proposal": "invoice""#))
        #expect(proposalOnly?.reactions == [])
        #expect(proposalOnly?.proposal == "invoice")
        #expect(ArtiseMessageFields.read(eventJSON: event(#""co.artise.note": 12"#)) == nil)
    }
    
    /// An emoji sent with the variation selector keeps it (the server accepts both) and still matches the plain one.
    @Test
    func variationSelectorIsKeptAndMatched() throws {
        let fields = try #require(ArtiseMessageFields.read(eventJSON: event(#""co.artise.reactions": ["✔\u{FE0F}"]"#)))
        #expect(fields.reactions == ["✔\u{FE0F}"])
        #expect(ArtiseMessageFields.plainEmoji(fields.reactions[0]) == "✔")
    }
    
    /// A file Ari posted from the notes says where it lives there.
    @Test
    func notePathIsRead() throws {
        let json = event(#""msgtype": "m.file", "co.artise.note": "business/documents/invoices/INV-2026-004.pdf""#)
        let fields = try #require(ArtiseMessageFields.read(eventJSON: json))
        #expect(fields.notePath == "business/documents/invoices/INV-2026-004.pdf")
        #expect(fields.reactions.isEmpty)
    }
    
    /// Labels: ✅ and ❌ on a proposal are "Approve" and "Decline"; other emojis, and a reminder, keep their own.
    @Test
    @MainActor
    func approveAndDeclineOnlyOnProposals() {
        let proposal = ArtiseMessageFields(reactions: ["✅", "❌"], proposal: "booking")
        #expect(ArtiseReactionLabels.label(for: "✅", fields: proposal) == ArtiseWorkspacesL10n.text("timeline_reaction_approve"))
        #expect(ArtiseReactionLabels.label(for: "❌", fields: proposal) == ArtiseWorkspacesL10n.text("timeline_reaction_decline"))
        #expect(ArtiseReactionLabels.label(for: "✅\u{FE0F}", fields: proposal) != nil)
        #expect(ArtiseReactionLabels.label(for: "👍", fields: proposal) == nil)
        #expect(ArtiseReactionLabels.label(for: "✅", fields: ArtiseMessageFields(reactions: ["✅"])) == nil)
        #expect(ArtiseReactionLabels.label(for: "✅", fields: nil) == nil)
    }
    
    /// The labels exist in the three languages, each in its own words.
    @Test
    @MainActor
    func labelsInTheThreeLanguages() {
        #expect(ArtiseWorkspacesL10n.text("timeline_reaction_approve", language: "en") == "Approve")
        #expect(ArtiseWorkspacesL10n.text("timeline_reaction_decline", language: "en") == "Decline")
        #expect(ArtiseWorkspacesL10n.text("timeline_reaction_approve", language: "es") == "Aprobar")
        #expect(ArtiseWorkspacesL10n.text("timeline_reaction_decline", language: "es") == "Rechazar")
        #expect(ArtiseWorkspacesL10n.text("timeline_reaction_approve", language: "pt") == "Aprovar")
        #expect(ArtiseWorkspacesL10n.text("timeline_reaction_decline", language: "pt") == "Recusar")
    }
    
    private func event(_ contentFields: String) -> String {
        #"{"type": "m.room.message", "sender": "@ari:artise.co", "content": {"msgtype": "m.text", "body": "…", \#(contentFields)}}"#
    }
}
