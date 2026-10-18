//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import QuickLook
import SwiftUI

/// A chat's photos and files, with the notes that use each one, as in the Android app. Unused ones can be deleted
/// together; one in use is only deleted after saying which notes show it, and taking it out of them.
struct NotesMediaScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    
    @State private var media: [MediaFile] = []
    @State private var hasLoaded = false
    @State private var showsUnusedOnly = false
    @State private var previewURL: URL?
    @State private var deleting: MediaFile?
    @State private var inUse: (path: String, usedBy: [String])?
    @State private var showsDeleteUnused = false
    @State private var problem: String?
    
    var body: some View {
        Form {
            Section {
                Picker(selection: $showsUnusedOnly) {
                    Text(ArtiseNotesL10n.text("screen_notes_media_all")).tag(false)
                    Text(String(format: ArtiseNotesL10n.text("screen_notes_media_unused"), unused.count)).tag(true)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            
            if hasLoaded, shown.isEmpty {
                Section {
                    Text(ArtiseNotesL10n.text(showsUnusedOnly ? "screen_notes_media_none_unused" : "screen_notes_media_empty"))
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                }
            } else {
                Section {
                    ForEach(shown, id: \.path) { file in
                        row(file)
                    }
                }
                if showsUnusedOnly, !unused.isEmpty {
                    Section {
                        ListRow(label: .action(title: String(format: ArtiseNotesL10n.text("screen_notes_media_delete_unused"), totalSize(unused)),
                                               icon: \.delete, role: .destructive),
                                kind: .button { showsDeleteUnused = true })
                    }
                }
            }
        }
        .compoundList()
        .onAppear { ArtiseAnalyticsClient.shared.screen(.notesMedia) }
        .navigationTitle(ArtiseNotesL10n.text("screen_notes_media_title"))
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($previewURL)
        .task { await load() }
        .task {
            for await _ in await service.repository.changes(roomID: roomID) {
                await load()
            }
        }
        .confirmationDialog(String(format: ArtiseNotesL10n.text("screen_notes_media_delete_title"), NotesFolderEntries.fileName(deleting?.path ?? "")),
                            isPresented: Binding(get: { deleting != nil }, set: {
                                if !$0 {
                                    deleting = nil
                                }
                            }), titleVisibility: .visible) {
            Button(ArtiseNotesL10n.text("screen_notes_media_delete"), role: .destructive) {
                if let file = deleting {
                    delete(file.path, removeFromNotes: false)
                }
            }
        } message: {
            Text(ArtiseNotesL10n.text("screen_notes_media_delete_message"))
        }
        .confirmationDialog(String(format: ArtiseNotesL10n.text("screen_notes_media_in_use_title"), NotesFolderEntries.fileName(inUse?.path ?? "")),
                            isPresented: Binding(get: { inUse != nil }, set: {
                                if !$0 {
                                    inUse = nil
                                }
                            }), titleVisibility: .visible) {
            Button(ArtiseNotesL10n.text("screen_notes_media_remove_and_delete"), role: .destructive) {
                if let file = inUse {
                    delete(file.path, removeFromNotes: true)
                }
            }
        } message: {
            Text(String(format: ArtiseNotesL10n.text("screen_notes_media_in_use_message"),
                        inUse?.usedBy.map(NotesFolderEntries.noteName).joined(separator: "\n") ?? ""))
        }
        .confirmationDialog(String.localizedStringWithFormat(ArtiseNotesL10n.text("screen_notes_media_delete_unused_title"), unused.count),
                            isPresented: $showsDeleteUnused, titleVisibility: .visible) {
            Button(ArtiseNotesL10n.text("screen_notes_media_delete"), role: .destructive) { deleteUnused() }
        } message: {
            Text(String(format: ArtiseNotesL10n.text("screen_notes_media_delete_unused_message"), totalSize(unused)))
        }
        .alert(problem ?? "", isPresented: Binding(get: { problem != nil }, set: {
            if !$0 {
                problem = nil
            }
        })) {
            Button(L10n.actionOk) { }
        }
    }
    
    private var unused: [MediaFile] {
        media.filter { $0.usedBy.isEmpty && $0.upload == nil }
    }
    
    private var shown: [MediaFile] {
        showsUnusedOnly ? unused : media
    }
    
    private func row(_ file: MediaFile) -> some View {
        let usedBy = file.usedBy.isEmpty
            ? ArtiseNotesL10n.text("screen_notes_media_not_used")
            : String.localizedStringWithFormat(ArtiseNotesL10n.text("screen_notes_media_used_in"), file.usedBy.count)
        let icon: KeyPath<CompoundIcons, Image> = NotesFolderEntries.isImage(file.path) ? \.image : \.files
        return ListRow(label: .default(title: NotesFolderEntries.fileName(file.path),
                                       description: usedBy + " · " + ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file),
                                       icon: icon),
                       kind: .button { open(file.path) })
            .contextMenu {
                Button { open(file.path) } label: {
                    Label(ArtiseNotesL10n.text("screen_notes_media_open"), icon: \.image)
                }
                Button(role: .destructive) { deleting = file } label: {
                    Label(ArtiseNotesL10n.text("screen_notes_media_delete"), icon: \.delete)
                }
            }
    }
    
    private func totalSize(_ files: [MediaFile]) -> String {
        ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.size }, countStyle: .file)
    }
    
    private func load() async {
        media = await ((try? service.repository.media(roomID: roomID)) ?? []).sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        hasLoaded = true
    }
    
    private func open(_ path: String) {
        let repository = service.repository
        Task {
            do {
                previewURL = try await repository.attachment(roomID: roomID, path: path)
            } catch {
                problem = ArtiseNotesL10n.text("screen_notes_attachment_unavailable")
            }
        }
    }
    
    private func delete(_ path: String, removeFromNotes: Bool) {
        deleting = nil
        inUse = nil
        let repository = service.repository
        Task {
            do {
                try await repository.deleteMedia(roomID: roomID, path: path, removeFromNotes: removeFromNotes)
            } catch let NotesError.inUse(_, usedBy) {
                inUse = (path, usedBy)
            } catch {
                problem = Self.problemText(for: error)
            }
        }
    }
    
    /// Each unused file is checked again before it's deleted; one that turns out to be used is kept, and asked about.
    private func deleteUnused() {
        let repository = service.repository
        let paths = unused.map(\.path)
        Task {
            for path in paths {
                do {
                    try await repository.deleteMedia(roomID: roomID, path: path, removeFromNotes: false)
                } catch let NotesError.inUse(_, usedBy) {
                    inUse = (path, usedBy)
                    return
                } catch {
                    problem = Self.problemText(for: error)
                    return
                }
            }
        }
    }
    
    private static func problemText(for error: Error) -> String {
        if case NotesError.network = error {
            return ArtiseNotesL10n.text("screen_notes_media_offline")
        }
        return ArtiseNotesL10n.text("screen_notes_media_failed")
    }
}
