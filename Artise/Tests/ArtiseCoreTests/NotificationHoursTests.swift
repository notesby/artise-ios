//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseCore
import Foundation
import Testing

struct NotificationHoursTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chihuahua") ?? .current
        return calendar
    }()
    
    /// Every day 09:00–18:00: sound inside the hours on any day, none before or after.
    @Test
    func everyDay() {
        let hours = NotificationHours(isOn: true, window: .init(start: 9 * 60, end: 18 * 60))
        #expect(hours.allowsSound(at: date("2026-10-19 09:00"), calendar: calendar)) // Monday
        #expect(hours.allowsSound(at: date("2026-10-24 17:59"), calendar: calendar)) // Saturday
        #expect(!hours.allowsSound(at: date("2026-10-19 18:00"), calendar: calendar))
        #expect(!hours.allowsSound(at: date("2026-10-19 08:59"), calendar: calendar))
    }
    
    /// Monday to Friday: the hours on weekdays, no sound all Saturday and Sunday.
    @Test
    func weekdays() {
        let hours = NotificationHours(isOn: true, schedule: .weekdays, window: .init(start: 9 * 60, end: 18 * 60))
        #expect(hours.allowsSound(at: date("2026-10-23 12:00"), calendar: calendar)) // Friday
        #expect(!hours.allowsSound(at: date("2026-10-24 12:00"), calendar: calendar)) // Saturday
        #expect(!hours.allowsSound(at: date("2026-10-25 12:00"), calendar: calendar)) // Sunday
        #expect(hours.allowsSound(at: date("2026-10-26 09:30"), calendar: calendar)) // Monday
    }
    
    /// Custom: each day its own hours; a day without hours has no sound.
    @Test
    func custom() {
        let hours = NotificationHours(isOn: true, schedule: .custom, days: [2: .init(start: 8 * 60, end: 12 * 60),
                                                                            7: .init(start: 10 * 60, end: 14 * 60)])
        #expect(hours.allowsSound(at: date("2026-10-19 11:00"), calendar: calendar)) // Monday
        #expect(!hours.allowsSound(at: date("2026-10-19 13:00"), calendar: calendar))
        #expect(hours.allowsSound(at: date("2026-10-24 13:00"), calendar: calendar)) // Saturday
        #expect(!hours.allowsSound(at: date("2026-10-20 11:00"), calendar: calendar)) // Tuesday has none
    }
    
    /// Hours that end before they start go past midnight and belong to the day they start.
    @Test
    func pastMidnight() {
        let hours = NotificationHours(isOn: true, schedule: .weekdays, window: .init(start: 18 * 60, end: 2 * 60))
        #expect(hours.allowsSound(at: date("2026-10-23 23:00"), calendar: calendar)) // Friday night
        #expect(hours.allowsSound(at: date("2026-10-24 01:59"), calendar: calendar)) // Friday's hours, on Saturday
        #expect(!hours.allowsSound(at: date("2026-10-24 23:00"), calendar: calendar)) // Saturday night
        #expect(!hours.allowsSound(at: date("2026-10-20 12:00"), calendar: calendar)) // Tuesday noon
    }
    
    /// The same start and end is the whole day; off always sounds.
    @Test
    func wholeDayAndOff() {
        let wholeMonday = NotificationHours(isOn: true, schedule: .custom, days: [2: .init(start: 0, end: 0)])
        #expect(wholeMonday.allowsSound(at: date("2026-10-19 00:00"), calendar: calendar))
        #expect(wholeMonday.allowsSound(at: date("2026-10-19 23:59"), calendar: calendar))
        #expect(!wholeMonday.allowsSound(at: date("2026-10-20 00:00"), calendar: calendar))
        #expect(NotificationHours(isOn: false, schedule: .custom).allowsSound(at: date("2026-10-21 03:00"), calendar: calendar))
    }
    
    /// Switching to custom starts from the hours shown: weekdays keeps Saturday and Sunday without hours.
    @Test
    func daysFromSchedule() {
        let window = NotificationHours.Window(start: 9 * 60, end: 18 * 60)
        let days = NotificationHours(schedule: .weekdays, window: window).daysFromSchedule
        #expect(days == [2: window, 3: window, 4: window, 5: window, 6: window])
        #expect(NotificationHours(window: window).daysFromSchedule.count == 7)
    }
    
    /// Mentions and replies sound anytime when allowed; Ari's reminders always do; others are quiet outside the hours.
    @Test
    func mentionsAndReminders() {
        let night = date("2026-10-21 23:00")
        let allowing = NotificationHours(isOn: true)
        #expect(allowing.silences(at: night, isMention: false, isReminder: false, calendar: calendar))
        #expect(!allowing.silences(at: night, isMention: true, isReminder: false, calendar: calendar))
        let strict = NotificationHours(isOn: true, allowsMentions: false)
        #expect(strict.silences(at: night, isMention: true, isReminder: false, calendar: calendar))
        #expect(!strict.silences(at: night, isMention: false, isReminder: true, calendar: calendar))
        #expect(!strict.silences(at: date("2026-10-21 12:00"), isMention: false, isReminder: false, calendar: calendar))
    }
    
    /// Quiet hours saved by earlier builds become the hours that sound at the same times: 22:00–07:00 quiet is
    /// 07:00–22:00 every day, and "All weekend" makes it Monday to Friday.
    @Test
    func earlierQuietHoursKeepTheirTimes() throws {
        let store = NotificationHoursStore(suiteName: "notification-hours-tests-earlier")
        let defaults = try #require(UserDefaults(suiteName: "notification-hours-tests-earlier"))
        store.remove(userID: "@a:x")
        defaults.set(Data(#"{"isOn":true,"start":1320,"end":420,"wholeWeekend":true,"allowsMentions":false}"#.utf8),
                     forKey: NotificationHoursStore.earlierKey("@a:x"))
        let hours = store.load(userID: "@a:x")
        #expect(hours == NotificationHours(isOn: true, schedule: .weekdays, window: .init(start: 420, end: 1320), allowsMentions: false))
        defaults.set(Data(#"{"isOn":true,"start":1260,"end":480,"days":[2,3],"allowsReminders":false}"#.utf8),
                     forKey: NotificationHoursStore.earlierKey("@a:x"))
        #expect(store.load(userID: "@a:x") == NotificationHours(isOn: true, window: .init(start: 480, end: 1260)))
        store.save(hours, userID: "@a:x")
        #expect(defaults.data(forKey: NotificationHoursStore.earlierKey("@a:x")) == nil)
        #expect(store.load(userID: "@a:x") == hours)
        store.remove(userID: "@a:x")
    }
    
    /// Each account keeps its own hours, custom days included; nothing saved means off.
    @Test
    func storedPerAccount() {
        let store = NotificationHoursStore(suiteName: "notification-hours-tests")
        store.remove(userID: "@a:x")
        store.remove(userID: "@b:x")
        #expect(store.load(userID: "@a:x") == NotificationHours())
        let custom = NotificationHours(isOn: true, schedule: .custom, days: [1: .init(start: 60, end: 120)])
        store.save(custom, userID: "@a:x")
        #expect(store.load(userID: "@a:x") == custom)
        #expect(store.load(userID: "@b:x") == NotificationHours())
        store.remove(userID: "@a:x")
        #expect(!store.load(userID: "@a:x").isOn)
    }
    
    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text) ?? .distantPast
    }
}
