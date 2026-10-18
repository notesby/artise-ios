//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// One note, read from the phone's copy. Checklist items tick with a tap; links lead to other notes or the web.
struct NoteScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    
    @State private var file: LocalFile?
    @State private var document = NoteDocument(markdown: "")
    @State private var paths: [String] = []
    @State private var notePaths: Set<String> = []
    @State private var hasLoaded = false
    @State private var route: NotesRoute?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if file?.hasLocalEdits == true {
                    Text(ArtiseNotesL10n.unsent)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
                
                if hasLoaded, file?.content == nil {
                    Text(ArtiseNotesL10n.notDownloaded)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                } else {
                    NoteMarkdownView(document: document,
                                     onLink: open,
                                     onToggle: toggle,
                                     embed: { AnyView(NoteEmbedCard(target: $0, paths: paths)) })
                }
            }
            .padding(16)
        }
        .background(.compound.bgCanvasDefault)
        .navigationTitle(NotesFolderEntries.noteName(path))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { _ = try? await service.repository.sync(roomID: roomID) }
        .navigationDestination(item: $route) { route in
            NotesDestination(service: service, route: route)
        }
        .task { await load() }
        .task {
            for await _ in await service.repository.changes(roomID: roomID) {
                await load()
            }
        }
    }
    
    private func load() async {
        let repository = service.repository
        file = try? await repository.file(roomID: roomID, path: path)
        let files = await (try? repository.files(roomID: roomID)) ?? []
        paths = files.map(\.path)
        notePaths = Set(files.filter(\.isNote).map(\.path))
        document = NoteDocument(markdown: file?.content ?? "")
        hasLoaded = true
    }
    
    private func open(_ link: NoteLink) {
        switch link {
        case .note(let target):
            // Photos and files embedded as links open with the attachments feature; notes open here.
            guard let resolved = NoteLinkResolver.resolve(target, in: paths), notePaths.contains(resolved) else { return }
            route = .note(roomID: roomID, path: resolved)
        case .web(let address):
            guard let url = URL(string: address) else { return }
            UIApplication.shared.open(url)
        }
    }
    
    /// Ticks or unticks the checklist item on `line`: saved on the phone at once, then sent.
    private func toggle(_ line: Int) {
        guard let content = file?.content, let ticked = ChecklistToggle.toggle(content, lineIndex: line) else { return }
        let repository = service.repository
        Task {
            try? await repository.editNote(roomID: roomID, path: path, content: ticked)
            repository.syncInBackground(roomID: roomID)
        }
    }
}

/// An embedded photo or file (`![[foto.jpg]]`), shown by name until it can be shown in full.
struct NoteEmbedCard: View {
    let target: String
    let paths: [String]
    
    var body: some View {
        let resolved = NoteLinkResolver.resolve(target, in: paths)
        HStack(spacing: 12) {
            CompoundIcon(icon)
                .foregroundStyle(.compound.iconSecondary)
            Text(NotesFolderEntries.fileName(resolved ?? target))
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if resolved == nil {
                Text(ArtiseNotesL10n.attachmentMissing)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }
        }
        .padding(12)
        .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var icon: KeyPath<CompoundIcons, Image> {
        NotesFolderEntries.isImage(target) ? \.image : \.files
    }
}
