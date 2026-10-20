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
    /// A link several notes answer to: the person picks one, opened once the sheet is gone.
    @State private var choice: NoteLinkChoice?
    @State private var chosenPath: String?
    @State private var previewURL: URL?
    @State private var document = NoteDocument(markdown: "")
    @State private var paths: [String] = []
    @State private var index = PageIndex.empty
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
                    if let header = document.frontmatter, header.hasFields {
                        NotePageFields(header: header)
                    }
                    NoteMarkdownView(document: document,
                                     onLink: open,
                                     onToggle: toggle,
                                     embed: { AnyView(embed($0)) })
                }
            }
            .padding(16)
        }
        .background(.compound.bgCanvasDefault)
        .onAppear { ArtiseAnalyticsClient.shared.screen(.note) }
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
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { route = .noteHistory(roomID: roomID, path: path) } label: {
                        Label(ArtiseNotesL10n.text("screen_notes_history_menu"), icon: \.history)
                    }
                } label: {
                    CompoundIcon(\.overflowHorizontal)
                }
                .accessibilityLabel(ArtiseNotesL10n.text("screen_notes_more"))
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
        .sheet(item: $choice, onDismiss: {
            if let chosenPath {
                self.chosenPath = nil
                open(chosenPath)
            }
        }) { choice in
            NoteLinkChoiceSheet(choice: choice) { path in
                chosenPath = path
                self.choice = nil
            }
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
        index = await PageIndex(paths: paths, pages: (try? repository.pages(roomID: roomID)) ?? [])
        document = NoteDocument(markdown: file?.content ?? "")
        hasLoaded = true
    }
    
    private func embed(_ target: String) -> some View {
        let resolved = NoteLinkResolver.resolve(target, in: paths)
        return NoteEmbedView(service: service, roomID: roomID, target: target, path: resolved,
                             size: resolved.flatMap { sizes[$0] }, upload: resolved.flatMap { uploads[$0] })
    }
    
    /// A link by name, title or alias opens the note; one that several notes answer to asks which, as the server
    /// does with its candidates; one to a note that doesn't exist yet offers to create it.
    private func open(_ link: NoteLink) {
        switch link {
        case .note(let target):
            switch index.resolve(target) {
            case .file(let resolved):
                open(resolved)
            case .ambiguous(let candidates):
                choice = NoteLinkChoice(name: target, candidates: candidates)
            case .missing:
                if !NoteLinkResolver.hasExtension(target) {
                    missingTarget = target
                }
            }
        case .web(let address):
            guard let url = URL(string: address) else { return }
            UIApplication.shared.open(url)
        }
    }
    
    private func open(_ resolved: String) {
        if notePaths.contains(resolved) {
            route = .note(roomID: roomID, path: resolved)
        } else {
            openFile(resolved)
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

/// The link's name and the notes that answer to it.
struct NoteLinkChoice: Identifiable {
    let name: String
    let candidates: [LinkCandidate]
    
    var id: String {
        name
    }
}

/// "Which one?": the notes sharing a name, each with its folder and summary, so the person opens the right one.
struct NoteLinkChoiceSheet: View {
    let choice: NoteLinkChoice
    let onPick: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    ForEach(choice.candidates) { candidate in
                        ListRow(label: .default(title: candidate.title, description: Self.description(candidate), icon: \.document),
                                kind: .button { onPick(candidate.path) })
                    }
                } header: {
                    Text(String(format: ArtiseNotesL10n.text("screen_notes_link_several"), choice.name))
                        .compoundListSectionHeader()
                }
            }
            .compoundList()
            .navigationTitle(ArtiseNotesL10n.text("screen_notes_link_which"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionCancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    /// "people · Ana, Hector's mother": the folder ("/" at the top), the type when the folder doesn't say it, and the summary.
    static func description(_ candidate: LinkCandidate) -> String {
        var parts = [candidate.folder.isEmpty ? "/" : candidate.folder]
        if !candidate.type.isEmpty, candidate.folder.lowercased() != candidate.type.lowercased() + "s" {
            parts.append(ArtiseNotesL10n.pageType(candidate.type))
        }
        if !candidate.summary.isEmpty {
            parts.append(candidate.summary)
        }
        return parts.joined(separator: " · ")
    }
}

/// A page's header as fields above its text: the type, and the other names it goes by.
struct NotePageFields: View {
    let header: NoteFrontmatter
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let type = header.type {
                Text(ArtiseNotesL10n.pageType(type))
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.compound.bgSubtleSecondary, in: Capsule())
            }
            if !header.aliases.isEmpty {
                Text(String(format: ArtiseNotesL10n.text("screen_notes_page_other_names"), header.aliases.joined(separator: ", ")))
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
        }
    }
}
