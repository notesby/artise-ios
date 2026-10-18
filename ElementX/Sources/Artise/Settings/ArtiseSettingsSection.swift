//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import ArtiseWorkspaces
import Compound
import SwiftUI

/// Artise's rows in Settings, under "Manage my app": Security (Artise ID's sign-in protection) when Artise ID
/// offers its security page, and Help from the workspace file.
struct ArtiseSettingsSection: View {
    private let session = ArtiseIDSession.shared
    private let workspaces = ArtiseWorkspaces.shared
    @State private var isPresentingSecurity = false
    @State private var isPresentingNotificationHours = false
    @State private var notesBackgroundSync = NotesBackgroundSyncStore().setting
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        if session.securityURL != nil || ArtiseRecoveryKeys.shared.hasKey {
            Section {
                ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_security_title"), icon: \.verified),
                        kind: .navigationLink { isPresentingSecurity = true })
            }
            .sheet(isPresented: $isPresentingSecurity) {
                ArtiseSecurityScreen()
            }
        }
        if let userID = workspaces.userID {
            Section {
                ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_notification_hours_title"), icon: \.time),
                        kind: .navigationLink { isPresentingNotificationHours = true })
            }
            .sheet(isPresented: $isPresentingNotificationHours) {
                ArtiseNotificationHoursScreen(userID: userID)
            }
        }
        if ArtiseNotes.shared.isAvailable {
            Section {
                ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_notes_background_title"), icon: \.download),
                        kind: .picker(selection: $notesBackgroundSync,
                                      items: NotesBackgroundSync.allCases.map { (title: Self.title($0), tag: $0) }))
            } footer: {
                Text(ArtiseWorkspacesL10n.text("screen_artise_notes_background_footer"))
                    .compoundListSectionFooter()
            }
            .onChange(of: notesBackgroundSync) { NotesBackgroundSyncStore().setting = notesBackgroundSync }
        }
        if workspaces.helpURL != nil || workspaces.contactURL != nil {
            Section {
                if let helpURL = workspaces.helpURL {
                    ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_help"), icon: \.helpSolid),
                            kind: .button { openURL(helpURL) })
                }
                if let contactURL = workspaces.contactURL {
                    ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_contact_admin"), icon: \.chat),
                            kind: .button { openURL(contactURL) })
                }
            }
        }
    }
    
    private static func title(_ setting: NotesBackgroundSync) -> String {
        switch setting {
        case .wifiOnly: ArtiseWorkspacesL10n.text("screen_artise_notes_background_wifi")
        case .wifiAndMobile: ArtiseWorkspacesL10n.text("screen_artise_notes_background_mobile")
        }
    }
}
