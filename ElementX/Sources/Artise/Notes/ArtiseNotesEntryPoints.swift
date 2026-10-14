//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI

/// The notes button in a top bar: the chats list's opens the chats with notes, a chat's opens its notes.
struct ArtiseNotesToolbarItem: ToolbarContent {
    let roomID: String?
    
    var body: some ToolbarContent {
        // Hidden when the workspace has no notes API.
        if ArtiseWorkspaces.shared.notesAPIURL != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ArtiseNotes.shared.open(roomID: roomID)
                } label: {
                    CompoundIcon(\.document)
                }
                .accessibilityLabel(ArtiseNotesL10n.title)
            }
        }
    }
}

/// The "Notes" row in a chat's details.
struct ArtiseNotesListRow: View {
    let roomID: String
    
    var body: some View {
        // Hidden when the workspace has no notes API.
        if ArtiseWorkspaces.shared.notesAPIURL != nil {
            ListRow(label: .default(title: ArtiseNotesL10n.title, icon: \.document),
                    kind: .navigationLink {
                        ArtiseNotes.shared.open(roomID: roomID)
                    })
        }
    }
}
