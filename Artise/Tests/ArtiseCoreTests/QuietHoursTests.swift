//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseCore
import Foundation
import Testing

struct QuietHoursTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chihuahua") ?? .current
        return calendar
    }()
    
    /// Overnight hours (22:00–07:00) cover the late evening and the next early morning, on the days they begin.
    @Test
    func overnight() {
        let weekdays = QuietHours(isOn: true, days: [2, 3, 4, 5, 6]) // Monday to Friday nights
        #expect(weekdays.isQuiet(at: date("2026-10-19 23:30"), calendar: calendar)) // Monday night
        #expect(weekdays.isQuiet(at: date("2026-10-20 06:59"), calendar: calendar)) // Tuesday early, from Monday
        #expect(!weekdays.isQuiet(at: date("2026-10-20 07:00"), calendar: calendar))
        #expect(!weekdays.isQuiet(at: date("2026-10-18 23:30"), calendar: calendar)) // Sunday night isn't listed
        #expect(weekdays.isQuiet(at: date("2026-10-24 06:00"), calendar: calendar)) // Saturday early, from Friday
        #expect(!weekdays.isQuiet(at: date("2026-10-25 06:00"), calendar: calendar)) // Sunday early, from Saturday
    }
    
    /// Daytime hours, off, and empty hours never quieten anything.
    @Test
    func daytimeAndOff() {
        let lunch = QuietHours(isOn: true, start: 14 * 60, end: 16 * 60)
        #expect(lunch.isQuiet(at: date("2026-10-21 15:00"), calendar: calendar))
        #expect(!lunch.isQuiet(at: date("2026-10-21 16:00"), calendar: calendar))
        #expect(!QuietHours(isOn: false).isQuiet(at: date("2026-10-21 23:00"), calendar: calendar))
        #expect(!QuietHours(isOn: true, start: 600, end: 600).isQuiet(at: date("2026-10-21 10:00"), calendar: calendar))
    }
    
    /// Mentions and Ari's reminders come through when allowed; everything else is quiet.
    @Test
    func mentionsAndReminders() {
        let night = date("2026-10-21 23:00")
        let allowing = QuietHours(isOn: true)
        #expect(allowing.silences(at: night, isMention: false, isReminder: false, calendar: calendar))
        #expect(!allowing.silences(at: night, isMention: true, isReminder: false, calendar: calendar))
        #expect(!allowing.silences(at: night, isMention: false, isReminder: true, calendar: calendar))
        let strict = QuietHours(isOn: true, allowsMentions: false, allowsReminders: false)
        #expect(strict.silences(at: night, isMention: true, isReminder: true, calendar: calendar))
        #expect(!strict.silences(at: date("2026-10-21 12:00"), isMention: false, isReminder: false, calendar: calendar))
    }
    
    /// Each account keeps its own hours; nothing saved means off.
    @Test
    func storedPerAccount() {
        let store = QuietHoursStore(suiteName: "quiet-hours-tests")
        store.remove(userID: "@a:x")
        store.remove(userID: "@b:x")
        #expect(store.load(userID: "@a:x") == QuietHours())
        store.save(QuietHours(isOn: true, start: 60), userID: "@a:x")
        #expect(store.load(userID: "@a:x").start == 60)
        #expect(store.load(userID: "@b:x") == QuietHours())
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
