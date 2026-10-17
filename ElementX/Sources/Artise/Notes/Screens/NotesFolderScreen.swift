//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import QuickLook
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
    @State private var downloadingNotes = 0
    @State private var chatName: String?
    @State private var route: NotesRoute?
    @State private var choicesCount = 0
    @State private var paths: [String] = []
    @State private var isNamingNote = false
    @State private var newNoteName = ""
    @State private var actions: NotesFolderActionsModel
    @State private var previewURL: URL?
    
    init(service: ArtiseNotesService, roomID: String, folder: String, title: String?) {
        self.service = service
        self.roomID = roomID
        self.folder = folder
        self.title = title
        _actions = State(initialValue: NotesFolderActionsModel(service: service, roomID: roomID))
    }
    
    var body: some View {
        Form {
            if choicesCount > 0 {
                Section {
                    NotesChoicesBanner(count: choicesCount) { route = .choices(roomID: roomID) }
                }
            }
            
            if downloadingNotes > 0 {
                Section {
                    Label {
                        Text(String(format: ArtiseWorkspacesL10n.text("screen_notes_updating"), downloadingNotes))
                            .font(.compound.bodySM)
                            .foregroundStyle(.compound.textSecondary)
                    } icon: {
                        ProgressView()
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
                }
            } else if status != .upToDate {
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
                            .contextMenu { actions.menu(for: entry) }
                    }
                }
            }
        }
        .compoundList()
        .onAppear { ArtiseAnalyticsClient.shared.screen(.notesFolder) }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await sync() }
        .navigationDestination(item: $route) { route in
            NotesDestination(service: service, route: route)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { route = .search(roomID: roomID) } label: {
                    CompoundIcon(\.search)
                }
                .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_search"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { route = .map(roomID: roomID) } label: {
                        Label(ArtiseNotesL10n.text("screen_notes_map"), icon: \.share)
                    }
                    Button { route = .media(roomID: roomID) } label: {
                        Label(ArtiseNotesL10n.text("screen_notes_media_title"), icon: \.image)
                    }
                    Button { route = .changes(roomID: roomID) } label: {
                        Label(ArtiseNotesL10n.text("screen_notes_history_menu"), icon: \.history)
                    }
                } label: {
                    CompoundIcon(\.overflowHorizontal)
                }
                .accessibilityLabel(ArtiseNotesL10n.text("screen_notes_more"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        newNoteName = ""
                        isNamingNote = true
                    } label: {
                        Label(ArtiseNotesL10n.text("screen_notes_new_note"), icon: \.document)
                    }
                    Button {
                        actions.folderName = ""
                        actions.isNamingFolder = true
                    } label: {
                        Label(ArtiseNotesL10n.text("screen_notes_new_folder"), icon: \.folder)
                    }
                } label: {
                    CompoundIcon(\.plus)
                }
                .accessibilityLabel(ArtiseNotesL10n.text("screen_notes_new"))
            }
        }
        .modifier(NotesFolderActionsDialogs(model: actions, folder: folder))
        .quickLookPreview($previewURL)
        .alert(ArtiseNotesL10n.text("screen_notes_new_note"), isPresented: $isNamingNote) {
            TextField(ArtiseNotesL10n.text("screen_notes_new_note_placeholder"), text: $newNoteName)
            Button(ArtiseNotesL10n.text("screen_notes_create")) { createNote() }
                .disabled(NoteNames.problem(with: newNoteName, in: folder, existingPaths: paths) != nil)
            Button(L10n.actionCancel, role: .cancel) { }
        } message: {
            Text(newNoteProblem ?? "")
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
        case .file(let name, let path, let isImage, let size):
            ListRow(label: .default(title: name,
                                    description: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                                    icon: Self.fileIcon(isImage: isImage)),
                    kind: .button { open(path) })
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
        paths = files.map(\.path)
        actions.paths = paths
        actions.folders = folders
        choicesCount = await ((try? repository.edits(roomID: roomID)) ?? []).filter { $0.state != .pending }.count
        downloadingNotes = await repository.activity(roomID: roomID).downloadingNotes
        if title == nil, folder.isEmpty {
            chatName = try? await repository.cachedChats().first { $0.roomID == roomID }?.name
        }
        hasLoaded = hasLoaded || !entries.isEmpty
    }
    
    /// Opens a photo or file in Quick Look, downloading it first when it isn't on the phone yet.
    private func open(_ path: String) {
        let repository = service.repository
        Task {
            do {
                previewURL = try await repository.attachment(roomID: roomID, path: path)
            } catch {
                actions.problem = ArtiseNotesL10n.text("screen_notes_attachment_unavailable")
            }
        }
    }
    
    /// Why the typed name can't be used yet, said under the field.
    private var newNoteProblem: String? {
        switch NoteNames.problem(with: newNoteName, in: folder, existingPaths: paths) {
        case .invalid where !newNoteName.isEmpty: ArtiseNotesL10n.text("screen_notes_name_invalid")
        case .exists: ArtiseNotesL10n.text("screen_notes_name_exists")
        default: nil
        }
    }
    
    /// Creates the note on the phone (it's sent with the next sync) and opens it in the editor.
    private func createNote() {
        let path = NoteNames.path(for: newNoteName, in: folder)
        let repository = service.repository
        Task {
            do {
                try await repository.createNote(roomID: roomID, path: path, content: "")
                route = .newNote(roomID: roomID, path: path)
            } catch {
                MXLog.error("Couldn't create a note: \(error)")
            }
        }
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
