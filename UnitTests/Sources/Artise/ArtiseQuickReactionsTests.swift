//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

/// The quick-reaction bar puts the reactions Ari asks for first; without them it's exactly as before.
@MainActor
struct ArtiseQuickReactionsTests {
    /// The offered emojis come first, in Ari's order, then the usual ones.
    @Test
    func offeredReactionsComeFirst() throws {
        let usual = try #require(makeActions(fields: nil)).reactions.map(\.key)
        let actions = try #require(makeActions(fields: ArtiseMessageFields(reactions: ["✅", "❌"], proposal: "invoice")))
        
        #expect(actions.reactions.map(\.key) == ["✅", "❌"] + usual)
    }
    
    /// A usual emoji that Ari also offers shows once, where Ari put it, even when one has the variation selector.
    @Test
    func anEmojiIsNeverShownTwice() throws {
        let actions = try #require(makeActions(fields: ArtiseMessageFields(reactions: ["👍", "✅"])))
        
        #expect(actions.reactions.map(\.key) == ["👍", "✅", "👎️", "🎉", "❤️"])
    }
    
    /// Without the field the bar is the usual one.
    @Test
    func theBarIsUnchangedWithoutTheField() throws {
        let actions = try #require(makeActions(fields: nil))
        
        #expect(actions.reactions.map(\.key) == ["👍️", "👎️", "🎉", "❤️"])
        #expect(actions.reactions.allSatisfy { $0.artiseLabel == nil })
    }
    
    /// The emojis this person uses most come before the usual four, most used first, and after Ari's.
    @Test
    func mostUsedEmojisComeBeforeTheUsualOnes() throws {
        let emojiProvider = EmojiProvider(appSettings: .volatile())
        emojiProvider.markEmojiAsFrequentlyUsed("🔥")
        emojiProvider.markEmojiAsFrequentlyUsed("🙏")
        emojiProvider.markEmojiAsFrequentlyUsed("🙏")
        
        let usual = try #require(makeActions(fields: nil, emojiProvider: emojiProvider))
        #expect(usual.reactions.map(\.key) == ["🙏", "🔥", "👍️", "👎️", "🎉", "❤️"])
        
        let offered = try #require(makeActions(fields: ArtiseMessageFields(reactions: ["✅", "❌"]), emojiProvider: emojiProvider))
        #expect(offered.reactions.map(\.key) == ["✅", "❌", "🙏", "🔥", "👍️", "👎️", "🎉", "❤️"])
    }
    
    /// On a proposal ✅ and ❌ carry their labels; on a reminder nothing does.
    @Test
    func labelsOnlyOnProposals() throws {
        let proposal = try #require(makeActions(fields: ArtiseMessageFields(reactions: ["✅", "❌"], proposal: "booking")))
        #expect(proposal.reactions[0].artiseLabel == ArtiseWorkspacesL10n.text("timeline_reaction_approve"))
        #expect(proposal.reactions[1].artiseLabel == ArtiseWorkspacesL10n.text("timeline_reaction_decline"))
        #expect(proposal.reactions[2].artiseLabel == nil)
        
        let reminder = try #require(makeActions(fields: ArtiseMessageFields(reactions: ["⏰", "🔁"])))
        #expect(reminder.reactions.allSatisfy { $0.artiseLabel == nil })
    }
    
    /// The fields are read from someone else's message, never from our own (Ari's messages aren't ours).
    @Test
    func theFactoryReadsTheFieldsFromOthersMessages() throws {
        let json = #"{"type": "m.room.message", "content": {"msgtype": "m.text", "body": "¿Mando la respuesta?", "co.artise.reactions": ["✅", "❌"], "co.artise.proposal": "inbox_reply"}}"#
        
        let theirs = try #require(buildItem(json: json, isOwn: false))
        #expect(theirs.properties.artiseFields == ArtiseMessageFields(reactions: ["✅", "❌"], proposal: "inbox_reply"))
        
        let ours = try #require(buildItem(json: json, isOwn: true))
        #expect(ours.properties.artiseFields == nil)
    }
    
    private func buildItem(json: String, isOwn: Bool) -> TextRoomTimelineItem? {
        let ownUserID = "@ana:artise.co"
        let factory = RoomTimelineItemFactory(userID: ownUserID,
                                              attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()),
                                              stateEventStringBuilder: RoomStateEventStringBuilder(userID: ownUserID))
        let body = "¿Mando la respuesta?"
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: .text(content: .init(body: body, formatted: nil)),
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        let event = EventTimelineItem(configuration: .init(sender: isOwn ? ownUserID : "@ari:artise.co",
                                                           isOwn: isOwn,
                                                           content: content,
                                                           artiseOriginalJSON: json))
        return factory.buildTimelineItem(for: EventTimelineItemProxy(item: event, uniqueID: .init("0")), isDM: false) as? TextRoomTimelineItem
    }
    
    private func makeActions(fields: ArtiseMessageFields?, emojiProvider: EmojiProviderProtocol = EmojiProvider(appSettings: .volatile())) -> TimelineItemMenuActions? {
        var properties = RoomTimelineItemProperties()
        properties.artiseFields = fields
        let item = TextRoomTimelineItem(id: .randomEvent,
                                        timestamp: .mock,
                                        isOutgoing: false,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: .init(id: "@ari:artise.co"),
                                        content: .init(body: "¿Mando la respuesta?"),
                                        properties: properties)
        return TimelineItemMenuActionProvider(timelineItem: item,
                                              canCurrentUserSendMessage: true,
                                              canCurrentUserRedactSelf: true,
                                              canCurrentUserRedactOthers: false,
                                              canCurrentUserPin: true,
                                              pinnedEventIDs: [],
                                              isViewSourceEnabled: true,
                                              areThreadsEnabled: true,
                                              isMultiSelectEnabled: false,
                                              timelineKind: .live,
                                              emojiProvider: emojiProvider)
            .makeActions()
    }
}
