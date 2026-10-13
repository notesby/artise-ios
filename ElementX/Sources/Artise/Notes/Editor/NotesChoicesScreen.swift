//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// "Choose a version": changes that couldn't be saved as they were, each with what happened and the ways out.
struct NotesChoicesScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    
    @State private var edits: [PendingEdit] = []
    @State private var hasLoaded = false
    @State private var combining: PendingEdit?
    
    var body: some View {
        Form {
            if hasLoaded, edits.isEmpty {
                Section {
                    Text(ArtiseNotesL10n.text("screen_notes_choices_empty"))
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                }
            }
            ForEach(edits, id: \.id) { edit in
                Section {
                    Text(Self.explanation(for: edit))
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textPrimary)
                    if showsVersions(edit) {
                        version(ArtiseNotesL10n.text("screen_notes_choice_mine"), edit.content)
                        version(ArtiseNotesL10n.text("screen_notes_choice_theirs"), edit.serverCopy?.content)
                    }
                    choices(for: edit)
                } header: {
                    Text(NotesFolderEntries.noteName(edit.path))
                        .compoundListSectionHeader()
                }
            }
        }
        .compoundList()
        .onAppear { ArtiseAnalyticsClient.shared.screen(.notesChoices) }
        .navigationTitle(ArtiseNotesL10n.text("screen_notes_choices_title"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $combining) { edit in
            NoteEditorScreen(service: service, roomID: roomID, path: edit.path, resolveEditID: edit.id) {
                combining = nil
            }
        }
        .task { await load() }
        .task {
            for await _ in await service.repository.changes(roomID: roomID) {
                await load()
            }
        }
    }
    
    private func showsVersions(_ edit: PendingEdit) -> Bool {
        (edit.state == .conflict && edit.kind == .save) || edit.state == .exists
    }
    
    private func version(_ title: String, _ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.compound.bodySMSemibold)
                .foregroundStyle(.compound.textSecondary)
            Text(text ?? "")
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(8)
        }
    }
    
    @ViewBuilder
    private func choices(for edit: PendingEdit) -> some View {
        switch (edit.state, edit.kind) {
        case (.conflict, .save):
            choice("screen_notes_choice_keep_mine") {
                try await service.repository.resolveConflict(roomID: roomID, editID: edit.id, content: edit.content ?? "")
            }
            Button(ArtiseNotesL10n.text("screen_notes_choice_combine")) { combining = edit }
            choice("screen_notes_choice_keep_theirs") { try await service.repository.discardEdit(roomID: roomID, editID: edit.id) }
        case (.deleted, _):
            choice("screen_notes_choice_keep_copy") { try await service.repository.keepDeletedNote(roomID: roomID, editID: edit.id) }
            choice("screen_notes_choice_discard") { try await service.repository.discardEdit(roomID: roomID, editID: edit.id) }
        case (.exists, _):
            choice("screen_notes_choice_keep_both") {
                let taken = try await service.repository.files(roomID: roomID).map(\.path)
                let newPath = NoteNames.freePath(for: edit.path, taken: taken)
                try await service.repository.saveUnderNewName(roomID: roomID, editID: edit.id, newPath: newPath)
            }
            choice("screen_notes_choice_discard") { try await service.repository.discardEdit(roomID: roomID, editID: edit.id) }
        case (_, .upload):
            choice("screen_notes_choice_discard") { try await service.repository.discardEdit(roomID: roomID, editID: edit.id) }
        default:
            choice("screen_notes_choice_keep_theirs") { try await service.repository.discardEdit(roomID: roomID, editID: edit.id) }
        }
    }
    
    private func choice(_ key: String, action: @escaping () async throws -> Void) -> some View {
        Button(ArtiseNotesL10n.text(key)) {
            let repository = service.repository
            let roomID = roomID
            Task {
                try? await action()
                repository.syncInBackground(roomID: roomID)
            }
        }
    }
    
    private func load() async {
        edits = await ((try? service.repository.edits(roomID: roomID)) ?? []).filter { $0.state != .pending }
        hasLoaded = true
    }
    
    static func explanation(for edit: PendingEdit) -> String {
        switch edit.state {
        case .conflict:
            ArtiseNotesL10n.text(edit.kind == .delete ? "screen_notes_choice_delete_conflict" : "screen_notes_choice_conflict")
        case .deleted:
            ArtiseNotesL10n.text("screen_notes_choice_deleted")
        case .exists:
            ArtiseNotesL10n.text("screen_notes_choice_exists")
        case .rejected, .pending:
            String(format: ArtiseNotesL10n.text("screen_notes_choice_rejected"), edit.error ?? "")
        }
    }
}

/// "2 notes need you to choose a version. Review", above a chat's notes while any change waits.
struct NotesChoicesBanner: View {
    let count: Int
    let onReview: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            CompoundIcon(\.warning)
                .foregroundStyle(.compound.iconCriticalPrimary)
            Text(String.localizedStringWithFormat(ArtiseNotesL10n.text("screen_notes_choices_banner"), count))
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(ArtiseNotesL10n.text("screen_notes_choices_review"), action: onReview)
                .font(.compound.bodyMDSemibold)
        }
    }
}
