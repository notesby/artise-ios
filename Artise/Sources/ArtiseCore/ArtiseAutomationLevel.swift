//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// How much an Ari automation or reminder post must be seen, as the bot marks it inside the message content:
/// `"co.artise.automation": {"id": "…", "level": "normal|important|critical"}`. The same rule as the Android app's
/// "Reminders" channel: important and critical posts break through Focus as Time Sensitive notifications, and
/// critical ones always make a sound, even in a chat whose notifications are silent.
public enum ArtiseAutomationLevel: Equatable, Sendable {
    case normal
    case important
    case critical
    
    public static let contentField = "co.artise.automation"
    
    /// Whether the post is a reminder (Time Sensitive on iOS, the "Reminders" channel on Android).
    public var isReminder: Bool {
        self != .normal
    }
    
    /// The level of the (decrypted) raw event, or `nil` when it isn't an automation post, is still encrypted or
    /// can't be read. An unknown level counts as `normal`, so a newer bot can't make an older app misbehave.
    public init?(rawEvent: String?) {
        guard let rawEvent, rawEvent.contains(Self.contentField),
              let data = rawEvent.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = event["content"] as? [String: Any],
              let automation = content[Self.contentField] as? [String: Any] else {
            return nil
        }
        switch automation["level"] as? String {
        case "important": self = .important
        case "critical": self = .critical
        default: self = .normal
        }
    }
}

#if canImport(UserNotifications)
public extension UNMutableNotificationContent {
    /// Makes an Ari reminder Time Sensitive; a critical one also makes `sound` even when the chat is silent.
    func applyArtiseAutomationLevel(_ level: ArtiseAutomationLevel?, sound: UNNotificationSound) {
        guard let level, level.isReminder else { return }
        interruptionLevel = .timeSensitive
        relevanceScore = 1
        if level == .critical {
            self.sound = sound
        }
    }
}
#endif
