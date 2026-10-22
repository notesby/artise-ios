//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI

/// "What's new": one card at the top of the chat list after an update, with the release's few changes, until it's
/// dismissed. A fresh install doesn't see it. Change `edition` and the `screen_artise_whats_new_*` texts per release.
@Observable
final class ArtiseWhatsNew {
    static let shared = ArtiseWhatsNew()
    /// This release's changes; bump it when the texts change.
    static let edition = "2026-10-23"
    static let itemKeys = ["screen_artise_whats_new_1", "screen_artise_whats_new_2", "screen_artise_whats_new_3"]
    
    private static let seenKey = "artise.whatsNew.seen"
    @ObservationIgnored private let defaults: UserDefaults
    private(set) var isShowing: Bool
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let seen = defaults.string(forKey: Self.seenKey) {
            isShowing = seen != Self.edition
        } else {
            // A fresh install: this edition counts as seen.
            defaults.set(Self.edition, forKey: Self.seenKey)
            isShowing = false
        }
    }
    
    func dismiss() {
        defaults.set(Self.edition, forKey: Self.seenKey)
        isShowing = false
    }
}

struct ArtiseWhatsNewCard: View {
    private let whatsNew = ArtiseWhatsNew.shared
    
    var body: some View {
        if whatsNew.isShowing {
            VStack(alignment: .leading, spacing: 8) {
                Text(ArtiseWorkspacesL10n.text("screen_artise_whats_new_title"))
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(ArtiseWhatsNew.itemKeys, id: \.self) { key in
                    Label {
                        Text(ArtiseWorkspacesL10n.text(key))
                            .font(.compound.bodyMD)
                            .foregroundStyle(.compound.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        CompoundIcon(\.check, size: .small, relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.iconAccentPrimary)
                    }
                }
                Button(ArtiseWorkspacesL10n.text("screen_artise_whats_new_done"), action: whatsNew.dismiss)
                    .buttonStyle(.compound(.secondary, size: .medium))
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
