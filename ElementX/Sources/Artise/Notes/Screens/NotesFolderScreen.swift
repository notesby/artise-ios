//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// A chat's notes, or one folder of them: subfolders, notes, then photos and files.
/// It works offline from the phone's copy and updates itself while it's open.
struct NotesFolderScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    /// "" for the chat's top level.
    let folder: String
    /// The chat's name for its top level; folders show their own name.
    let title: String?
    
    @State private var entries: [NotesFolderEntry] = []
    @State private var hasLoaded = false
    @State private var status = NotesSyncStatus.upToDate
    @State private var chatName: String?
    @State private var route: NotesRoute?
    
    var body: some View {
        Form {
            if status != .upToDate {
                Section {
                    NotesStatusLine(status: status)
                }
            }
            
            if hasLoaded, entries.isEmpty {
                Section {
                    Text(folder.isEmpty ? ArtiseNotesL10n.folderEmpty : ArtiseNotesL10n.folderIsEmpty)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            }
        }
        .compoundList()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await sync() }
        .navigationDestination(item: $route) { route in
            NotesDestination(service: service, route: route)
        }
        .task { await load() }
        .task { await followChanges() }
        .task {
            await sync()
            // Live updates from the chat's `co.artise.notes` state while notes are open.
            await service.follow(roomID: roomID)
        }
    }
    
    private var navigationTitle: String {
        if !folder.isEmpty {
            return NotesFolderEntries.fileName(folder)
        }
        return title ?? chatName ?? ArtiseNotesL10n.title
    }
    
    @ViewBuilder
    private func row(_ entry: NotesFolderEntry) -> some View {
        switch entry {
        case .folder(let name, let path, let notes, let files):
            ListRow(label: .default(title: name, description: Self.counts(notes: notes, files: files), icon: \.folder),
                    kind: .navigationLink { route = .folder(roomID: roomID, path: path) })
        case .note(let name, let path, let hasLocalEdits):
            ListRow(label: .default(title: name, description: hasLocalEdits ? ArtiseNotesL10n.unsent : nil, icon: \.document),
                    kind: .navigationLink { route = .note(roomID: roomID, path: path) })
        case .file(let name, _, let isImage, let size):
            // Photos and files open from the notes that show them; managing them comes with the files feature.
            ListRow(label: .default(title: name,
                                    description: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                                    icon: Self.fileIcon(isImage: isImage)),
                    kind: .label)
        }
    }
    
    private static func fileIcon(isImage: Bool) -> KeyPath<CompoundIcons, Image> {
        isImage ? \.image : \.files
    }
    
    /// "3 notes · 2 files", leaving out what a folder doesn't hold.
    private static func counts(notes: Int, files: Int) -> String? {
        var parts: [String] = []
        if notes > 0 {
            parts.append(ArtiseNotesL10n.folderCount(notes))
        }
        if files > 0 {
            parts.append(ArtiseNotesL10n.folderFileCount(files))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    
    private func load() async {
        let repository = service.repository
        let files = await (try? repository.files(roomID: roomID)) ?? []
        let folders = await (try? repository.folders(roomID: roomID)) ?? []
        entries = NotesFolderEntries.entries(files: files, folder: folder, allFolders: folders)
        if title == nil, folder.isEmpty {
            chatName = try? await repository.cachedChats().first { $0.roomID == roomID }?.name
        }
        hasLoaded = hasLoaded || !entries.isEmpty
    }
    
    private func followChanges() async {
        for await _ in await service.repository.changes(roomID: roomID) {
            await load()
        }
    }
    
    private func sync() async {
        do {
            status = try await NotesSyncStatus(report: service.repository.sync(roomID: roomID))
        } catch {
            status = NotesSyncStatus(error: error)
        }
        await load()
        hasLoaded = true
    }
}
