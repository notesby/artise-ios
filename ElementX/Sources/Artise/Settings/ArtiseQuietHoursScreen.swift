//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import Compound
import SwiftUI

/// Settings → Quiet hours for this workspace: notifications arrive without sound and without lighting the screen,
/// on the chosen days and hours. Mentions and Ari's reminders can still ring.
struct ArtiseQuietHoursScreen: View {
    let userID: String
    @State private var hours: QuietHours
    @Environment(\.dismiss) private var dismiss
    private let store = ArtiseQuietHoursScreen.store
    
    static let store = QuietHoursStore(suiteName: AppSettings.suiteName)
    
    init(userID: String) {
        self.userID = userID
        _hours = State(initialValue: Self.store.load(userID: userID))
    }
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_title"), icon: \.notificationsOff),
                            kind: .toggle($hours.isOn))
                } footer: {
                    Text(ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_description"))
                        .compoundListSectionFooter()
                }
                if hours.isOn {
                    Section {
                        DatePicker(ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_from"), selection: time(\.start), displayedComponents: .hourAndMinute)
                        DatePicker(ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_to"), selection: time(\.end), displayedComponents: .hourAndMinute)
                    }
                    Section {
                        ForEach(Self.weekdays, id: \.self) { weekday in
                            ListRow(label: .plain(title: Calendar.current.weekdaySymbols[weekday - 1].capitalized),
                                    kind: .multiSelection(isSelected: hours.days.contains(weekday)) { toggle(weekday) })
                        }
                    } header: {
                        Text(ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_days"))
                            .compoundListSectionHeader()
                    }
                    Section {
                        ListRow(label: .plain(title: ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_mentions")),
                                kind: .toggle($hours.allowsMentions))
                        ListRow(label: .plain(title: ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_reminders")),
                                kind: .toggle($hours.allowsReminders))
                    }
                }
            }
            .compoundList()
            .navigationTitle(ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionDone) { dismiss() }
                }
            }
        }
        .onChange(of: hours) { store.save(hours, userID: userID) }
    }
    
    /// Monday first, as people in Mexico and Brazil read a week.
    private static let weekdays = [2, 3, 4, 5, 6, 7, 1]
    
    private func toggle(_ weekday: Int) {
        if hours.days.contains(weekday) {
            hours.days.remove(weekday)
        } else {
            hours.days.insert(weekday)
        }
    }
    
    /// A time of day, kept as minutes after midnight.
    private func time(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(hours[keyPath: keyPath] * 60))
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            hours[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}
