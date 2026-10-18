//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import Compound
import SwiftUI

/// Settings → Notification hours for this workspace, as on Android: when its notifications may sound, every day,
/// Monday to Friday or each day its own hours. Outside them they arrive without sound and without lighting the
/// screen. Mentions and replies can sound anytime; Ari's reminders always do.
struct ArtiseNotificationHoursScreen: View {
    let userID: String
    @State private var hours: NotificationHours
    @Environment(\.dismiss) private var dismiss
    private let store = ArtiseNotificationHoursScreen.store
    
    static let store = NotificationHoursStore(suiteName: AppSettings.suiteName)
    /// Monday first, as on Android.
    private static let weekOrder = [2, 3, 4, 5, 6, 7, 1]
    
    init(userID: String) {
        self.userID = userID
        _hours = State(initialValue: Self.store.load(userID: userID))
    }
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    ListRow(label: .default(title: text("title"), icon: \.time),
                            kind: .toggle($hours.isOn))
                } footer: {
                    Text(text("description"))
                        .compoundListSectionFooter()
                }
                if hours.isOn {
                    scheduleSection
                    if hours.schedule == .custom {
                        ForEach(Self.weekOrder, id: \.self) { weekday in
                            daySection(weekday)
                        }
                    } else {
                        windowSection
                    }
                    Section {
                        ListRow(label: .plain(title: text("mentions")),
                                kind: .toggle($hours.allowsMentions))
                    }
                }
            }
            .compoundList()
            .navigationTitle(text("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionDone) { dismiss() }
                }
            }
        }
        .onChange(of: hours) { store.save(hours, userID: userID) }
    }
    
    private var scheduleSection: some View {
        Section {
            ForEach(NotificationHours.Schedule.allCases, id: \.self) { schedule in
                ListRow(label: .plain(title: Self.title(schedule)),
                        kind: .selection(isSelected: hours.schedule == schedule) { choose(schedule) })
            }
        } header: {
            Text(text("days"))
                .compoundListSectionHeader()
        } footer: {
            switch hours.schedule {
            case .everyDay: EmptyView()
            case .weekdays: Text(text("weekdays_footer")).compoundListSectionFooter()
            case .custom: Text(text("custom_footer")).compoundListSectionFooter()
            }
        }
    }
    
    private var windowSection: some View {
        Section {
            timeRow(text("from"), minute: $hours.window.start)
            timeRow(text("until"), minute: $hours.window.end)
        } header: {
            Text(text("hours"))
                .compoundListSectionHeader()
        }
    }
    
    private func daySection(_ weekday: Int) -> some View {
        Section {
            ListRow(label: .plain(title: Self.dayName(weekday)), kind: .toggle(dayIsOn(weekday)))
            if let window = hours.days[weekday] {
                timeRow(text("from"), minute: Binding { window.start } set: { hours.days[weekday]?.start = $0 })
                timeRow(text("until"), minute: Binding { window.end } set: { hours.days[weekday]?.end = $0 })
            }
        }
    }
    
    private func timeRow(_ title: String, minute: Binding<Int>) -> some View {
        ListRow(kind: .custom {
            DatePicker(title, selection: Self.time(minute), displayedComponents: .hourAndMinute)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textPrimary)
                .padding(ListRowPadding.insets)
        })
    }
    
    /// Custom starts from the hours shown, so switching doesn't lose them.
    private func choose(_ schedule: NotificationHours.Schedule) {
        if schedule == .custom, hours.schedule != .custom {
            hours.days = hours.daysFromSchedule
        }
        hours.schedule = schedule
    }
    
    /// A day turned on gets the hours from Every day and Monday to Friday.
    private func dayIsOn(_ weekday: Int) -> Binding<Bool> {
        Binding { hours.days[weekday] != nil } set: { isOn in
            hours.days[weekday] = isOn ? hours.window : nil
        }
    }
    
    private func text(_ key: String) -> String {
        ArtiseWorkspacesL10n.text("screen_artise_notification_hours_" + key)
    }
    
    private static func title(_ schedule: NotificationHours.Schedule) -> String {
        switch schedule {
        case .everyDay: ArtiseWorkspacesL10n.text("screen_artise_notification_hours_every_day")
        case .weekdays: ArtiseWorkspacesL10n.text("screen_artise_notification_hours_weekdays")
        case .custom: ArtiseWorkspacesL10n.text("screen_artise_notification_hours_custom")
        }
    }
    
    /// "Lunes", in the app's language.
    private static func dayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        let name = formatter.standaloneWeekdaySymbols[weekday - 1]
        return name.prefix(1).uppercased() + name.dropFirst()
    }
    
    /// Minutes after midnight as a time on a fixed day, for the picker.
    private static func time(_ minute: Binding<Int>) -> Binding<Date> {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        return Binding {
            calendar.date(byAdding: .minute, value: minute.wrappedValue, to: day) ?? day
        } set: { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            minute.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}
