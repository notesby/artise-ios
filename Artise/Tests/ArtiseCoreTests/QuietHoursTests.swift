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
    
    /// Overnight hours (22:00–07:00) cover every late evening and early morning, as on Android.
    @Test
    func overnight() {
        let night = QuietHours(isOn: true)
        #expect(night.isQuiet(at: date("2026-10-19 23:30"), calendar: calendar)) // Monday night
        #expect(night.isQuiet(at: date("2026-10-20 06:59"), calendar: calendar))
        #expect(!night.isQuiet(at: date("2026-10-20 07:00"), calendar: calendar))
        #expect(!night.isQuiet(at: date("2026-10-24 12:00"), calendar: calendar)) // Saturday noon, weekend not chosen
    }
    
    /// "All weekend": Saturday and Sunday are quiet all day; weekdays keep only the night window.
    @Test
    func wholeWeekend() {
        let weekend = QuietHours(isOn: true, wholeWeekend: true)
        #expect(weekend.isQuiet(at: date("2026-10-24 12:00"), calendar: calendar)) // Saturday
        #expect(weekend.isQuiet(at: date("2026-10-25 18:00"), calendar: calendar)) // Sunday
        #expect(!weekend.isQuiet(at: date("2026-10-26 12:00"), calendar: calendar)) // Monday noon
        #expect(weekend.isQuiet(at: date("2026-10-26 06:00"), calendar: calendar)) // Monday early, the night window
    }
    
    /// Daytime hours and off never quieten anything outside them.
    @Test
    func daytimeAndOff() {
        let lunch = QuietHours(isOn: true, start: 14 * 60, end: 16 * 60)
        #expect(lunch.isQuiet(at: date("2026-10-21 15:00"), calendar: calendar))
        #expect(!lunch.isQuiet(at: date("2026-10-21 16:00"), calendar: calendar))
        #expect(!QuietHours(isOn: false).isQuiet(at: date("2026-10-21 23:00"), calendar: calendar))
        #expect(!QuietHours(isOn: false, wholeWeekend: true).isQuiet(at: date("2026-10-24 12:00"), calendar: calendar))
    }
    
    /// Mentions and replies come through when allowed; Ari's reminders always do; everything else is quiet.
    @Test
    func mentionsAndReminders() {
        let night = date("2026-10-21 23:00")
        let allowing = QuietHours(isOn: true)
        #expect(allowing.silences(at: night, isMention: false, isReminder: false, calendar: calendar))
        #expect(!allowing.silences(at: night, isMention: true, isReminder: false, calendar: calendar))
        let strict = QuietHours(isOn: true, allowsMentions: false)
        #expect(strict.silences(at: night, isMention: true, isReminder: false, calendar: calendar))
        #expect(!strict.silences(at: night, isMention: false, isReminder: true, calendar: calendar))
        #expect(!strict.silences(at: date("2026-10-21 12:00"), isMention: false, isReminder: false, calendar: calendar))
    }
    
    /// The four night windows are Android's.
    @Test
    func windowsMatchAndroid() {
        #expect(QuietHours.windows.map { "\($0.start)-\($0.end)" } == ["1200-480", "1260-480", "1320-420", "1380-420"])
    }
    
    /// Hours saved by an earlier build (with chosen days and a reminders switch) still load, keeping their times.
    @Test
    func earlierSavedHoursStillLoad() throws {
        let old = #"{"isOn":true,"start":1260,"end":480,"days":[2,3],"allowsMentions":false,"allowsReminders":false}"#
        let hours = try JSONDecoder().decode(QuietHours.self, from: Data(old.utf8))
        #expect(hours == QuietHours(isOn: true, start: 1260, end: 480, wholeWeekend: false, allowsMentions: false))
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
