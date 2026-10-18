//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// A workspace's quiet hours, as on Android: during them its notifications still arrive, but without sound and without
/// lighting the screen (iOS can't hide them without Apple's filtering permission). A night window every day, and the
/// whole weekend if chosen. Mentions and replies can still ring; Ari's reminders always do.
public struct QuietHours: Codable, Equatable, Sendable {
    public var isOn: Bool
    /// Minutes after midnight; `start` after `end` means overnight (22:00–07:00).
    public var start: Int
    public var end: Int
    /// Saturday and Sunday are quiet all day.
    public var wholeWeekend: Bool
    /// Mentions and replies (the same "mention" the server marks) still ring.
    public var allowsMentions: Bool
    
    /// The night windows to choose from, the same as Android's.
    public static let windows: [(start: Int, end: Int)] = [(20 * 60, 8 * 60), (21 * 60, 8 * 60), (22 * 60, 7 * 60), (23 * 60, 7 * 60)]
    
    public init(isOn: Bool = false, start: Int = 22 * 60, end: Int = 7 * 60, wholeWeekend: Bool = false, allowsMentions: Bool = true) {
        self.isOn = isOn
        self.start = start
        self.end = end
        self.wholeWeekend = wholeWeekend
        self.allowsMentions = allowsMentions
    }
    
    /// Hours saved by earlier builds (chosen days, a reminders switch) keep their switch and times.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(isOn: container.decodeIfPresent(Bool.self, forKey: .isOn) ?? false,
                      start: container.decodeIfPresent(Int.self, forKey: .start) ?? 22 * 60,
                      end: container.decodeIfPresent(Int.self, forKey: .end) ?? 7 * 60,
                      wholeWeekend: container.decodeIfPresent(Bool.self, forKey: .wholeWeekend) ?? false,
                      allowsMentions: container.decodeIfPresent(Bool.self, forKey: .allowsMentions) ?? true)
    }
    
    /// Whether `date` falls in quiet hours: the night window, or any time on a weekend when chosen.
    public func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isOn else { return false }
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        if wholeWeekend, parts.weekday == 1 || parts.weekday == 7 {
            return true
        }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start <= end {
            return minute >= start && minute < end
        }
        return minute >= start || minute < end
    }
    
    /// Whether this notification is quietened now. Ari's reminders never are.
    public func silences(at date: Date, isMention: Bool, isReminder: Bool, calendar: Calendar = .current) -> Bool {
        guard !isReminder, !(isMention && allowsMentions) else { return false }
        return isQuiet(at: date, calendar: calendar)
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
    /// In quiet hours: no sound and no screen wake, unless it's a reminder or an allowed mention.
    func applyArtiseQuietHours(_ hours: QuietHours, now: Date = .now, isMention: Bool, isReminder: Bool) {
        guard hours.silences(at: now, isMention: isMention, isReminder: isReminder) else { return }
        sound = nil
        interruptionLevel = .passive
    }
}
#endif
