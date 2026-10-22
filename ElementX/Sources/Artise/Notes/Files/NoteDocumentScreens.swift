//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import PDFKit
import QuickLook
import SwiftUI

/// What a file in the notes opens in, by its name: notes in the editor, PDFs in the viewer, photos as themselves,
/// anything else (an Office file) as a download.
nonisolated enum ArtiseNoteDocument {
    enum Kind: Equatable {
        case note
        case pdf
        case photo
        case file
    }
    
    static let noteExtensions: Set = ["md", "txt"]
    
    static func kind(of path: String) -> Kind {
        let name = NotesFolderEntries.fileName(path)
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return .file }
        let ext = name[name.index(after: dot)...].lowercased()
        if noteExtensions.contains(ext) {
            return .note
        }
        if ext == "pdf" {
            return .pdf
        }
        return NotesFolderEntries.isImage(path) ? .photo : .file
    }
    
    static func isPDF(_ path: String) -> Bool {
        kind(of: path) == .pdf
    }
}

/// A file Ari posted from the notes, opened from the chat: the notes' own copy, updated first so it's the current
/// one. A note opens in the editor, a PDF in the viewer, a photo or any other file in Quick Look.
struct ArtiseNoteDocumentView: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    let onClose: () -> Void
    
    @State private var stage = Stage.loading
    @State private var previewURL: URL?
    
    private enum Stage: Equatable {
        case loading
        case editor
        case pdf
        case quickLook
        case unavailable
    }
    
    var body: some View {
        Group {
            switch stage {
            case .editor:
                NoteEditorScreen(service: service, roomID: roomID, path: path, onDone: onClose)
            case .pdf:
                NotePDFSheet(service: service, roomID: roomID, path: path, onClose: onClose)
            case .loading, .quickLook, .unavailable:
                ElementNavigationStack {
                    Group {
                        if stage == .unavailable {
                            Text(ArtiseNotesL10n.text("screen_notes_attachment_unavailable"))
                                .font(.compound.bodyLG)
                                .foregroundStyle(.compound.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(32)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.compound.bgCanvasDefault)
                    .navigationTitle(NotesFolderEntries.fileName(path))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(action: onClose) {
                                CompoundIcon(\.close)
                            }
                            .accessibilityLabel(L10n.actionClose)
                        }
                    }
                }
                .quickLookPreview($previewURL)
                .onChange(of: previewURL) { _, url in
                    // Quick Look closed: nothing is left to show.
                    if url == nil, stage == .quickLook {
                        onClose()
                    }
                }
            }
        }
        .task { await open() }
    }
    
    private func open() async {
        let repository = service.repository
        // The latest copy first; offline, the phone's copy is what there is.
        _ = try? await repository.sync(roomID: roomID)
        switch ArtiseNoteDocument.kind(of: path) {
        case .note:
            let file = try? await repository.file(roomID: roomID, path: path)
            stage = file?.content != nil ? .editor : .unavailable
        case .pdf:
            stage = .pdf
        case .photo, .file:
            if let url = try? await repository.attachment(roomID: roomID, path: path) {
                previewURL = url
                stage = .quickLook
            } else {
                stage = .unavailable
            }
        }
    }
}

/// The PDF viewer on its own, with a close button, for when there's no notes screen to push it from.
struct NotePDFSheet: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    let onClose: () -> Void
    
    var body: some View {
        ElementNavigationStack {
            NotePDFScreen(service: service, roomID: roomID, path: path)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onClose) {
                            CompoundIcon(\.close)
                        }
                        .accessibilityLabel(L10n.actionClose)
                    }
                }
        }
    }
}

/// A PDF from the notes, page by page, from the phone's copy (downloaded first when it isn't there yet).
struct NotePDFScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    
    @State private var document: PDFDocument?
    @State private var failed = false
    
    var body: some View {
        Group {
            if let document {
                NotePDFView(document: document)
            } else if failed {
                Text(ArtiseNotesL10n.text("screen_notes_attachment_unavailable"))
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.compound.bgCanvasDefault)
        .navigationTitle(NotesFolderEntries.fileName(path))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    
    private func load() async {
        let repository = service.repository
        guard let url = try? await repository.attachment(roomID: roomID, path: path), let loaded = PDFDocument(url: url) else {
            failed = true
            return
        }
        document = loaded
    }
}

/// PDFKit's view: pages one under the other, fitted to the width.
struct NotePDFView: UIViewRepresentable {
    let document: PDFDocument
    
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .compound.bgCanvasDefault
        view.document = document
        return view
    }
    
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
    }
}
