//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import Compound
import SwiftUI

/// Artise's rows in Settings, under "Manage my app": Security (Artise ID's sign-in protection) when Artise ID
/// offers its security page.
struct ArtiseSettingsSection: View {
    private let session = ArtiseIDSession.shared
    @State private var isPresentingSecurity = false
    
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
    }
}
