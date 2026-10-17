//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// A workspace's quiet hours: during them its notifications still arrive, but without sound and without lighting the
/// screen (iOS can't hide them without Apple's filtering permission). Mentions and Ari's reminders can still ring.
public struct QuietHours: Codable, Equatable, Sendable {
    public var isOn: Bool
    /// Minutes after midnight; `start` after `end` means overnight (22:00–07:00).
    public var start: Int
    public var end: Int
    /// `Calendar` weekdays (1 = Sunday … 7 = Saturday) on which quiet hours begin.
    public var days: Set<Int>
    public var allowsMentions: Bool
    public var allowsReminders: Bool
    
    public init(isOn: Bool = false, start: Int = 22 * 60, end: Int = 7 * 60, days: Set<Int> = Set(1...7),
                allowsMentions: Bool = true, allowsReminders: Bool = true) {
        self.isOn = isOn
        self.start = start
        self.end = end
        self.days = days
        self.allowsMentions = allowsMentions
        self.allowsReminders = allowsReminders
    }
    
    /// Whether `date` falls in quiet hours. Overnight hours belong to the day they begin on.
    public func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isOn, start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let weekday = parts.weekday ?? 1
        let yesterday = weekday == 1 ? 7 : weekday - 1
        if start < end {
            return days.contains(weekday) && minute >= start && minute < end
        }
        return (days.contains(weekday) && minute >= start) || (days.contains(yesterday) && minute < end)
    }
    
    /// Whether this notification is quietened now.
    public func silences(at date: Date, isMention: Bool, isReminder: Bool, calendar: Calendar = .current) -> Bool {
        guard isQuiet(at: date, calendar: calendar) else { return false }
        if isMention, allowsMentions {
            return false
        }
        return !(isReminder && allowsReminders)
    }
}

/// Quiet hours per account, in the defaults the app shares with the notification extension.
public struct QuietHoursStore: Sendable {
    private let suiteName: String?
    
    /// `suiteName`: the app group; `nil` for the app's own defaults (tests).
    public init(suiteName: String?) {
        self.suiteName = suiteName
    }
    
    public func load(userID: String) -> QuietHours {
        guard let data = defaults?.data(forKey: Self.key(userID)),
              let hours = try? JSONDecoder().decode(QuietHours.self, from: data) else {
            return QuietHours()
        }
        return hours
    }
    
    public func save(_ hours: QuietHours, userID: String) {
        defaults?.set(try? JSONEncoder().encode(hours), forKey: Self.key(userID))
    }
    
    public func remove(userID: String) {
        defaults?.removeObject(forKey: Self.key(userID))
    }
    
    private var defaults: UserDefaults? {
        suiteName.map { UserDefaults(suiteName: $0) } ?? .standard
    }
    
    static func key(_ userID: String) -> String {
        "artise.quietHours." + userID
    }
}

#if canImport(UserNotifications)
public extension UNMutableNotificationContent {
    /// In quiet hours: no sound and no screen wake, unless it's a mention or a reminder that's allowed through.
    func applyArtiseQuietHours(_ hours: QuietHours, now: Date = .now, isMention: Bool, isReminder: Bool) {
        guard hours.silences(at: now, isMention: isMention, isReminder: isReminder) else { return }
        sound = nil
        interruptionLevel = .passive
    }
}
#endif
