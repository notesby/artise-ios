//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// A workspace's notification hours, as on Android: when its notifications may sound. Outside them they still
/// arrive, but without sound and without lighting the screen (iOS can't hide them without Apple's filtering
/// permission). Mentions and replies can sound anytime; Ari's reminders always do.
public struct NotificationHours: Codable, Equatable, Sendable {
    /// Which days have hours.
    public enum Schedule: String, Codable, CaseIterable, Sendable {
        /// The same hours every day.
        case everyDay
        /// The same hours Monday to Friday; Saturday and Sunday have none.
        case weekdays
        /// Each day its own hours, or none.
        case custom
    }
    
    /// Hours that start on a day, in minutes after midnight. `end` before `start` goes past midnight (18:00–02:00
    /// belongs to the day it starts); the same `start` and `end` is the whole day.
    public struct Window: Codable, Equatable, Hashable, Sendable {
        public var start: Int
        public var end: Int
        
        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }
        
        /// How long it lasts, in minutes: 1 to 1440.
        public var length: Int {
            let length = (end - start + Self.day) % Self.day
            return length == 0 ? Self.day : length
        }
        
        static let day = 24 * 60
    }
    
    /// Off: every notification sounds as usual.
    public var isOn: Bool
    public var schedule: Schedule
    /// The hours for every day or for weekdays.
    public var window: Window
    /// The hours for each day in `custom`, by `Calendar` weekday (1 is Sunday, 7 is Saturday). A missing day has none.
    public var days: [Int: Window]
    /// Mentions and replies (the same "mention" the server marks) sound anytime.
    public var allowsMentions: Bool
    
    /// The default hours, 07:00 to 22:00, the opposite of the earlier quiet hours' default.
    public static let defaultWindow = Window(start: 7 * 60, end: 22 * 60)
    /// Monday to Friday, as `Calendar` weekdays.
    public static let weekdays = 2...6
    
    public init(isOn: Bool = false,
                schedule: Schedule = .everyDay,
                window: Window = defaultWindow,
                days: [Int: Window] = [:],
                allowsMentions: Bool = true) {
        self.isOn = isOn
        self.schedule = schedule
        self.window = window
        self.days = days
        self.allowsMentions = allowsMentions
    }
    
    /// The hours that start on `weekday`, if any.
    public func window(on weekday: Int) -> Window? {
        switch schedule {
        case .everyDay: window
        case .weekdays: Self.weekdays.contains(weekday) ? window : nil
        case .custom: days[weekday]
        }
    }
    
    /// Each day with the same hours as `everyDay` or `weekdays` show now, for switching to `custom`.
    public var daysFromSchedule: [Int: Window] {
        var days: [Int: Window] = [:]
        for weekday in 1...7 {
            days[weekday] = window(on: weekday)
        }
        return days
    }
    
    /// Whether `date` is inside the hours: those that started today, or yesterday's still going past midnight.
    public func allowsSound(at date: Date, calendar: Calendar = .current) -> Bool {
        guard isOn else { return true }
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let today = parts.weekday ?? 1
        let yesterday = today == 1 ? 7 : today - 1
        if let window = window(on: today), (0..<window.length).contains(minute - window.start) {
            return true
        }
        if let window = window(on: yesterday), (0..<window.length).contains(minute + Window.day - window.start) {
            return true
        }
        return false
    }
    
    /// Whether this notification comes without sound now. Ari's reminders never do.
    public func silences(at date: Date, isMention: Bool, isReminder: Bool, calendar: Calendar = .current) -> Bool {
        guard !isReminder, !(isMention && allowsMentions) else { return false }
        return !allowsSound(at: date, calendar: calendar)
    }
}

extension NotificationHours {
    /// The quiet hours earlier builds saved (a quiet window every night, and maybe the whole weekend), as the
    /// notification hours that sound at exactly the same times.
    init(quietHours old: EarlierQuietHours) {
        self.init(isOn: old.isOn ?? false,
                  schedule: old.wholeWeekend == true ? .weekdays : .everyDay,
                  window: Window(start: old.end ?? 7 * 60, end: old.start ?? 22 * 60),
                  allowsMentions: old.allowsMentions ?? true)
    }
    
    struct EarlierQuietHours: Decodable {
        var isOn: Bool?
        var start: Int?
        var end: Int?
        var wholeWeekend: Bool?
        var allowsMentions: Bool?
    }
}

/// Notification hours per account, in the defaults the app shares with the notification extension.
public struct NotificationHoursStore: Sendable {
    private let suiteName: String?
    
    /// `suiteName`: the app group; `nil` for the app's own defaults (tests).
    public init(suiteName: String?) {
        self.suiteName = suiteName
    }
    
    /// The saved hours; quiet hours saved by earlier builds are read as the same hours.
    public func load(userID: String) -> NotificationHours {
        if let data = defaults?.data(forKey: Self.key(userID)),
           let hours = try? JSONDecoder().decode(NotificationHours.self, from: data) {
            return hours
        }
        if let data = defaults?.data(forKey: Self.earlierKey(userID)),
           let old = try? JSONDecoder().decode(NotificationHours.EarlierQuietHours.self, from: data) {
            return NotificationHours(quietHours: old)
        }
        return NotificationHours()
    }
    
    public func save(_ hours: NotificationHours, userID: String) {
        defaults?.set(try? JSONEncoder().encode(hours), forKey: Self.key(userID))
        defaults?.removeObject(forKey: Self.earlierKey(userID))
    }
    
    public func remove(userID: String) {
        defaults?.removeObject(forKey: Self.key(userID))
        defaults?.removeObject(forKey: Self.earlierKey(userID))
    }
    
    private var defaults: UserDefaults? {
        suiteName.map { UserDefaults(suiteName: $0) } ?? .standard
    }
    
    static func key(_ userID: String) -> String {
        "artise.notificationHours." + userID
    }
    
    static func earlierKey(_ userID: String) -> String {
        "artise.quietHours." + userID
    }
}

#if canImport(UserNotifications)
public extension UNMutableNotificationContent {
    /// Outside the notification hours: no sound and no screen wake, unless it's a reminder or an allowed mention.
    func applyArtiseNotificationHours(_ hours: NotificationHours, now: Date = .now, isMention: Bool, isReminder: Bool) {
        guard hours.silences(at: now, isMention: isMention, isReminder: isReminder) else { return }
        sound = nil
        interruptionLevel = .passive
    }
}
#endif
