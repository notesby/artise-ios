//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI

/// The sticker button at the end of an empty message field, as in the Android app; it opens the sticker picker.
struct ArtiseStickerButton: View {
    let roomID: String?
    
    var body: some View {
        if let roomID, ArtiseStickers.shared.service != nil {
            Button {
                ArtiseStickers.shared.openPicker(roomID: roomID)
            } label: {
                CompoundIcon(\.sticker, size: .medium, relativeTo: .compound.headingLG)
                    .foregroundStyle(.compound.iconSecondary)
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ArtiseStickersL10n.text("screen_stickers_open"))
        }
    }
}
