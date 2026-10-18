//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// A chat's history: every change to its notes, newest first, grouped by day, with who it was for and the files it
/// touched, as in the Android app. Older pages load at the end of the list. It needs a connection.
struct NotesChangesScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    
    @State private var changes: [NotesChange] = []
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var failed = false
    @State private var route: NotesRoute?
    
    var body: some View {
        Form {
            NotesHistoryStatus(isLoading: isLoading && changes.isEmpty, failed: failed && changes.isEmpty,
                               isEmpty: !isLoading && !failed && changes.isEmpty, emptyKey: "screen_notes_history_empty") {
                Task { await loadMore() }
            }
            ForEach(HistoryDays.grouped(changes, at: \.at).indices, id: \.self) { index in
                let group = HistoryDays.grouped(changes, at: \.at)[index]
                Section {
                    ForEach(group.items, id: \.commit) { change in
                        changeRow(change)
                    }
                } header: {
                    Text(NotesHistoryFormat.day(group.day))
                        .compoundListSectionHeader()
                }
            }
            if hasMore {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await loadMore() }
                }
            }
        }
        .compoundList()
        .onAppear { ArtiseAnalyticsClient.shared.screen(.notesHistory) }
        .navigationTitle(ArtiseNotesL10n.text("screen_notes_history_title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { route in
            NotesDestination(service: service, route: route)
        }
        .task { await loadMore() }
    }
    
    private func changeRow(_ change: NotesChange) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NotesHistoryFormat.time(change.at) + " · " + NotesHistoryFormat.label(change.author))
                .font(.compound.bodySMSemibold)
                .foregroundStyle(.compound.textSecondary)
            ForEach(change.files, id: \.path) { file in
                Button { open(file) } label: {
                    HStack(spacing: 8) {
                        CompoundIcon(NotesHistoryFormat.icon(file.change), size: .small, relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.iconSecondary)
                            .accessibilityLabel(ArtiseNotesL10n.text(NotesHistoryFormat.descriptionKey(file.change)))
                        Text(NotesHistoryFormat.fileText(file))
                            .font(.compound.bodyMD)
                            .foregroundStyle(.compound.textPrimary)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                .disabled(file.change == .deleted || !file.path.hasSuffix(".md"))
            }
        }
        .padding(.vertical, 4)
    }
    
    /// A changed note opens as it is now; deleted ones and photos stay as they are in the list.
    private func open(_ file: ChangedFile) {
        route = .note(roomID: roomID, path: file.path)
    }
    
    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        failed = false
        defer { isLoading = false }
        do {
            let page = try await service.repository.changeHistory(roomID: roomID, before: changes.last?.commit)
            changes += page.changes
            hasMore = page.more && !page.changes.isEmpty
        } catch {
            failed = true
            hasMore = false
        }
    }
}

/// A note's history: its saved versions, newest first; one opens read-only.
struct NoteHistoryScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    
    @State private var versions: [NoteVersion] = []
    @State private var isLoading = true
    @State private var failed = false
    @State private var route: NotesRoute?
    
    var body: some View {
        Form {
            NotesHistoryStatus(isLoading: isLoading, failed: failed, isEmpty: !isLoading && !failed && versions.isEmpty,
                               emptyKey: "screen_notes_note_history_empty") {
                Task { await load() }
            }
            ForEach(HistoryDays.grouped(versions, at: \.at).indices, id: \.self) { index in
                let group = HistoryDays.grouped(versions, at: \.at)[index]
                Section {
                    ForEach(group.items, id: \.commit) { version in
                        ListRow(label: .default(title: NotesHistoryFormat.time(version.at) + " · " + NotesHistoryFormat.label(version.author),
                                                icon: \.history),
                                kind: .navigationLink { route = .noteVersion(roomID: roomID, path: path, commit: version.commit, at: version.at) })
                    }
                } header: {
                    Text(NotesHistoryFormat.day(group.day))
                        .compoundListSectionHeader()
                }
            }
        }
        .compoundList()
        .onAppear { ArtiseAnalyticsClient.shared.screen(.noteHistory) }
        .navigationTitle(String(format: ArtiseNotesL10n.text("screen_notes_note_history_title"), NotesFolderEntries.noteName(path)))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { route in
            NotesDestination(service: service, route: route)
        }
        .task { await load() }
    }
    
    private func load() async {
        isLoading = true
        failed = false
        do {
            versions = try await service.repository.history(roomID: roomID, path: path)
        } catch {
            failed = true
        }
        isLoading = false
    }
}

/// A note as it was in an earlier version, read-only.
struct NoteVersionScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    let commit: String
    let at: String
    
    @State private var document: NoteDocument?
    @State private var failed = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(format: ArtiseNotesL10n.text("screen_notes_version_from"),
                            NotesHistoryFormat.day(HistoryDays.date(at)) + ", " + NotesHistoryFormat.time(at)))
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                if let document {
                    NoteMarkdownView(document: document, onLink: { _ in }, onToggle: nil, embed: { target in
                        AnyView(Text("🖼 " + target).font(.compound.bodyMD).foregroundStyle(.compound.textSecondary))
                    })
                } else if failed {
                    NotesHistoryStatus(isLoading: false, failed: true, isEmpty: false, emptyKey: "") {
                        Task { await load() }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
        }
        .background(.compound.bgCanvasDefault)
        .onAppear { ArtiseAnalyticsClient.shared.screen(.noteVersion) }
        .navigationTitle(NotesFolderEntries.noteName(path))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    
    private func load() async {
        failed = false
        do {
            let note = try await service.repository.noteAt(roomID: roomID, path: path, commit: commit)
            document = NoteDocument(markdown: note.content)
        } catch {
            failed = true
        }
    }
}

/// Loading, offline (with Try again) or empty, above a history list.
private struct NotesHistoryStatus: View {
    let isLoading: Bool
    let failed: Bool
    let isEmpty: Bool
    let emptyKey: String
    let onRetry: () -> Void
    
    var body: some View {
        if isLoading {
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        } else if failed {
            Section {
                Text(ArtiseNotesL10n.text("screen_notes_history_offline"))
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textSecondary)
                Button(ArtiseNotesL10n.text("screen_notes_history_retry"), action: onRetry)
            }
        } else if isEmpty {
            Section {
                Text(ArtiseNotesL10n.text(emptyKey))
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textSecondary)
            }
        }
    }
}

/// How history entries read: days, times, who and what.
enum NotesHistoryFormat {
    static func day(_ date: Date?) -> String {
        guard let date else { return "" }
        if Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date) {
            return date.formatted(.relative(presentation: .named)).capitalized(with: .current)
        }
        return date.formatted(date: .complete, time: .omitted)
    }
    
    static func time(_ iso: String) -> String {
        HistoryDays.date(iso)?.formatted(date: .omitted, time: .shortened) ?? ""
    }
    
    static func label(_ author: ChangeAuthor) -> String {
        switch ChangeLabel(author) {
        case .text(let key, let arguments):
            ChangeLabel.tidy(String(format: ArtiseNotesL10n.text(key), arguments: arguments))
        case .plain(let name):
            name
        }
    }
    
    static func fileText(_ file: ChangedFile) -> String {
        let name = NotesFolderEntries.noteName(file.path)
        guard let from = file.from, file.change == .renamed else { return name }
        return String(format: ArtiseNotesL10n.text("screen_notes_history_renamed"), NotesFolderEntries.noteName(from), name)
    }
    
    static func icon(_ change: FileChange) -> KeyPath<CompoundIcons, Image> {
        switch change {
        case .added: \.plus
        case .deleted: \.delete
        case .renamed, .copied: \.edit
        case .modified: \.document
        }
    }
    
    static func descriptionKey(_ change: FileChange) -> String {
        "a11y_notes_history_" + change.rawValue
    }
}
