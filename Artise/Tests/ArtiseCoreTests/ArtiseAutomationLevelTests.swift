//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseCore
import Testing

struct ArtiseAutomationLevelTests {
    /// A critical post reads as critical and is a reminder.
    @Test
    func criticalPost() {
        let level = ArtiseAutomationLevel(rawEvent: post(level: "critical"))
        #expect(level == .critical)
        #expect(level?.isReminder == true)
    }
    
    /// An important post reads as important and is a reminder.
    @Test
    func importantPost() {
        let level = ArtiseAutomationLevel(rawEvent: post(level: "important"))
        #expect(level == .important)
        #expect(level?.isReminder == true)
    }
    
    /// A normal post stays an ordinary message.
    @Test
    func normalPost() {
        let level = ArtiseAutomationLevel(rawEvent: post(level: "normal"))
        #expect(level == .normal)
        #expect(level?.isReminder == false)
    }
    
    /// An unknown or missing level from a newer bot counts as normal.
    @Test
    func unknownLevelsAreNormal() {
        #expect(ArtiseAutomationLevel(rawEvent: post(level: "urgent")) == .normal)
        #expect(ArtiseAutomationLevel(rawEvent: post(level: nil)) == .normal)
    }
    
    /// A message without the field is not an automation post.
    @Test
    func ordinaryMessage() {
        #expect(ArtiseAutomationLevel(rawEvent: #"{"type":"m.room.message","content":{"msgtype":"m.text","body":"Hi"}}"#) == nil)
    }
    
    /// The field outside the content, a still encrypted event, or broken JSON give no level.
    @Test
    func unreadableEvents() {
        #expect(ArtiseAutomationLevel(rawEvent: #"{"type":"m.room.message","co.artise.automation":{"level":"critical"},"content":{"body":"x"}}"#) == nil)
        #expect(ArtiseAutomationLevel(rawEvent: #"{"type":"m.room.encrypted","content":{"algorithm":"m.megolm.v1.aes-sha2","ciphertext":"AwgA"}}"#) == nil)
        #expect(ArtiseAutomationLevel(rawEvent: #"{"content":{"co.artise.automation":"#) == nil)
        #expect(ArtiseAutomationLevel(rawEvent: #"{"content":{"co.artise.automation":"critical"}}"#) == nil)
        #expect(ArtiseAutomationLevel(rawEvent: nil) == nil)
        #expect(ArtiseAutomationLevel(rawEvent: "") == nil)
    }
    
    private func post(level: String?) -> String {
        let levelField = level.map { #","level":"\#($0)""# } ?? ""
        return #"{"type":"m.room.message","event_id":"$an_event","content":{"msgtype":"m.text","body":"💊 Toma tu pastilla","co.artise.automation":{"id":"a1"\#(levelField)}}}"#
    }
}
