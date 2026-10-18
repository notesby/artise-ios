//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import QuickLook
import SwiftUI

/// One note, read from the phone's copy. Checklist items tick with a tap; links lead to other notes or the web.
struct NoteScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    /// Opens the editor right away, for a note just created.
    var startsEditing = false
    
    @State private var file: LocalFile?
    @State private var isEditing = false
    @State private var missingTarget: String?
    @State private var previewURL: URL?
    @State private var document = NoteDocument(markdown: "")
    @State private var paths: [String] = []
    @State private var notePaths: Set<String> = []
    @State private var sizes: [String: Int64] = [:]
    @State private var uploads: [String: UploadStatus] = [:]
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
                                     embed: { AnyView(embed($0)) })
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.actionEdit) { isEditing = true }
                    .disabled(hasLoaded && file?.content == nil && !startsEditing)
            }
        }
        .alert(missingTarget.map { String(format: ArtiseNotesL10n.text("screen_notes_missing_note_create"), $0) } ?? "",
               isPresented: Binding(get: { missingTarget != nil }, set: {
                   if !$0 {
                       missingTarget = nil
                   }
               })) {
            Button(ArtiseNotesL10n.text("screen_notes_create")) { createMissingNote() }
            Button(L10n.actionCancel, role: .cancel) { }
        }
        .quickLookPreview($previewURL)
        .fullScreenCover(isPresented: $isEditing) {
            NoteEditorScreen(service: service, roomID: roomID, path: path) { isEditing = false }
        }
        .task {
            await load()
            if startsEditing {
                isEditing = true
            }
        }
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
        sizes = Dictionary(files.map { ($0.path, $0.size) }, uniquingKeysWith: { first, _ in first })
        uploads = await (try? repository.uploads(roomID: roomID)) ?? [:]
        document = NoteDocument(markdown: file?.content ?? "")
        hasLoaded = true
    }
    
    private func embed(_ target: String) -> some View {
        let resolved = NoteLinkResolver.resolve(target, in: paths)
        return NoteEmbedView(service: service, roomID: roomID, target: target, path: resolved,
                             size: resolved.flatMap { sizes[$0] }, upload: resolved.flatMap { uploads[$0] })
    }
    
    private func open(_ link: NoteLink) {
        switch link {
        case .note(let target):
            guard let resolved = NoteLinkResolver.resolve(target, in: paths) else {
                // A link to a note that doesn't exist yet: offer to create it.
                if !NoteLinkResolver.hasExtension(target) {
                    missingTarget = target
                }
                return
            }
            if notePaths.contains(resolved) {
                route = .note(roomID: roomID, path: resolved)
            } else {
                openFile(resolved)
            }
        case .web(let address):
            guard let url = URL(string: address) else { return }
            UIApplication.shared.open(url)
        }
    }
    
    /// Creates the note a link points to, next to this one (or at the path the link names), and opens it.
    private func createMissingNote() {
        guard let target = missingTarget else { return }
        let folder = target.contains("/") ? "" : NotesFolderEntries.parentFolder(of: path)
        let newPath = NoteNames.path(for: target, in: folder)
        let repository = service.repository
        Task {
            try? await repository.createNote(roomID: roomID, path: newPath, content: "")
            route = .newNote(roomID: roomID, path: newPath)
        }
    }
    
    /// A linked photo or file (`[[factura.pdf]]`) opens in Quick Look, downloaded first if needed.
    private func openFile(_ path: String) {
        let repository = service.repository
        Task {
            if let url = try? await repository.attachment(roomID: roomID, path: path) {
                previewURL = url
            }
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
