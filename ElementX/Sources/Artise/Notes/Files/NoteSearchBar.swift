//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI

/// What a search in a document has to say.
enum NoteSearchStatus: Equatable {
    /// Nothing typed yet.
    case idle
    /// "3 of 12".
    case found(position: Int, total: Int)
    /// Words typed, nothing found.
    case none
    /// The file can't be searched (too big, or a kind with no text).
    case unavailable
}

/// The search field above a document or the editor: typing finds as you go, the count says where you are
/// ("3 of 12"), the arrows (and return) go to the next or previous match.
struct NoteSearchBar: View {
    @Binding var query: String
    let status: NoteSearchStatus
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            if status == .unavailable {
                Text(ArtiseNotesL10n.text("screen_notes_find_unavailable"))
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                CompoundIcon(\.search, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconSecondary)
                TextField(ArtiseNotesL10n.text("screen_notes_find_placeholder"), text: $query)
                    .font(.compound.bodyMD)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit(onNext)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_find"))
                Text(statusText)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.updatesFrequently)
                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_find_previous"))
                .disabled(!hasMatches)
                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_find_next"))
                .disabled(!hasMatches)
            }
            Button(action: onClose) {
                CompoundIcon(\.close, size: .small, relativeTo: .compound.bodyMD)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(L10n.actionClose)
        }
        .foregroundStyle(.compound.iconPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.compound.bgSubtleSecondary)
        .onAppear { isFocused = status != .unavailable }
    }
    
    private var hasMatches: Bool {
        if case .found = status {
            return true
        }
        return false
    }
    
    private var statusText: String {
        switch status {
        case .idle, .unavailable: ""
        case .found(let position, let total): ArtiseNotesL10n.findCount(position, of: total)
        case .none: ArtiseNotesL10n.text("screen_notes_find_none")
        }
    }
}
