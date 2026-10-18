//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import Compound
import SwiftUI

/// Ari, pinned at the top of the chat list with what to ask it. Shows when the workspace names Ari's account.
struct ArtiseAssistantRow: View {
    private let workspaces = ArtiseWorkspaces.shared
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        if let branding = workspaces.branding, branding.assistantUserID != nil {
            Button {
                if let url = workspaces.assistantChatURL() {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 12) {
                    CompoundIcon(\.chat, size: .medium, relativeTo: .compound.bodyLGSemibold)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(workspaces.accent ?? .compound.bgActionPrimaryRest, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(branding.assistantName ?? "Ari")
                            .font(.compound.bodyLGSemibold)
                            .foregroundStyle(.compound.textPrimary)
                        Text(branding.naming(ArtiseWorkspacesL10n.text("screen_artise_assistant_hint")))
                            .font(.compound.bodyMD)
                            .foregroundStyle(.compound.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    CompoundIcon(\.pin, size: .small, relativeTo: .compound.bodyMD)
                        .foregroundStyle(.compound.iconTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }
}
