//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import SwiftUI

/// Signing out in Artise's words: it names the workspace, says what happens, and that Artise ID signs out too.
enum ArtiseSignOutText {
    /// Settings: "Sign out of Panadería Sol".
    static var settingsItem: String {
        workspaceName.map { String(format: ArtiseWorkspacesL10n.text("screen_artise_sign_out_from"), $0) } ?? L10n.screenSignoutPreferenceItem
    }
    
    static var confirmationTitle: String {
        workspaceName.map { String(format: ArtiseWorkspacesL10n.text("screen_artise_sign_out_title"), $0) } ?? L10n.screenSignoutConfirmationDialogTitle
    }
    
    static var confirmationMessage: String {
        let content = workspaceName.map { String(format: ArtiseWorkspacesL10n.text("screen_artise_sign_out_content"), $0) }
            ?? ArtiseWorkspacesL10n.text("screen_artise_sign_out_content_unnamed")
        // Artise signs in to one workspace at a time, so signing out of it also forgets Artise ID.
        guard ArtiseIDSession.shared.isSignedIn else { return content }
        return content + "\n\n" + ArtiseWorkspacesL10n.text("screen_artise_sign_out_artise_id")
    }
    
    private static var workspaceName: String? {
        ArtiseWorkspaces.shared.current?.displayName
    }
}
