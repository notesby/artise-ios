//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import Compound
import SwiftUI

/// Artise's rows in Settings, under "Manage my app": Security (Artise ID's sign-in protection) when Artise ID
/// offers its security page, and Help from the workspace file.
struct ArtiseSettingsSection: View {
    private let session = ArtiseIDSession.shared
    private let workspaces = ArtiseWorkspaces.shared
    @State private var isPresentingSecurity = false
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        if session.securityURL != nil {
            Section {
                ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_security_title"), icon: \.verified),
                        kind: .navigationLink { isPresentingSecurity = true })
            }
            .sheet(isPresented: $isPresentingSecurity) {
                ArtiseSecurityScreen()
            }
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
}
