//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import Compound
import SwiftUI

/// Settings → Quiet hours for this workspace, as on Android: notifications arrive without sound and without lighting
/// the screen during a night window, and all weekend if chosen. Mentions and replies can still ring; Ari's reminders
/// always do.
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
                        ForEach(windows.indices, id: \.self) { index in
                            let window = windows[index]
                            ListRow(label: .plain(title: Self.windowText(window)),
                                    kind: .selection(isSelected: hours.start == window.start && hours.end == window.end) {
                                        hours.start = window.start
                                        hours.end = window.end
                                    })
                        }
                    } header: {
                        Text(ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_hours"))
                            .compoundListSectionHeader()
                    }
                    Section {
                        ListRow(label: .plain(title: ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_weekend")),
                                kind: .toggle($hours.wholeWeekend))
                        ListRow(label: .plain(title: ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_mentions")),
                                kind: .toggle($hours.allowsMentions))
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
    
    /// Android's four windows, plus the saved one when an earlier build chose other times.
    private var windows: [(start: Int, end: Int)] {
        let saved = (start: hours.start, end: hours.end)
        return QuietHours.windows.contains { $0 == saved } ? QuietHours.windows : QuietHours.windows + [saved]
    }
    
    /// "De 22:00 a 07:00", with the same 24-hour times as Android.
    private static func windowText(_ window: (start: Int, end: Int)) -> String {
        String(format: ArtiseWorkspacesL10n.text("screen_artise_quiet_hours_window"), clock(window.start), clock(window.end))
    }
    
    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}
