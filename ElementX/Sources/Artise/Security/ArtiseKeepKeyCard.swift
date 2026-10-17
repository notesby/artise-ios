//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI

/// Once, for someone signed in on only this phone: keep the recovery key (or a passkey) for a phone change,
/// especially to Android, where iCloud Keychain doesn't reach. Never blocks the chat list.
struct ArtiseKeepKeyCard: View {
    private let keys = ArtiseRecoveryKeys.shared
    
    var body: some View {
        if keys.showsKeepKeyCard {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(ArtiseWorkspacesL10n.text("screen_artise_keep_key_card"))
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    CompoundIcon(\.key, size: .small, relativeTo: .compound.bodyMD)
                        .foregroundStyle(.compound.iconSecondary)
                }
                HStack(spacing: 12) {
                    Button(ArtiseWorkspacesL10n.text("screen_artise_keep_key_card_show")) {
                        ArtiseWorkspacePresenter.present(ArtiseSecurityScreen())
                    }
                    .buttonStyle(.compound(.secondary, size: .medium))
                    Button(ArtiseWorkspacesL10n.text("screen_artise_keep_key_card_later"), action: keys.dismissKeepKeyCard)
                        .buttonStyle(.compound(.tertiary, size: .medium))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
