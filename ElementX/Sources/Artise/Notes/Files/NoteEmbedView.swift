//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import QuickLook
import SwiftUI

/// An embedded photo or file (`![[foto.jpg]]`) in a note: a photo shows itself, a document shows as a card that
/// opens on tap. Opening a note downloads its photos on any connection; documents download when tapped.
struct NoteEmbedView: View {
    let service: ArtiseNotesService
    let roomID: String
    let target: String
    /// The file the target resolves to, `nil` when it isn't in the chat.
    let path: String?
    let size: Int64?
    let upload: UploadStatus?
    
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var failed = false
    @State private var previewURL: URL?
    @State private var showsCancelUpload = false
    /// A PDF, Office file or CSV, opened in its viewer.
    @State private var showsDocument = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let path, NotesFolderEntries.isImage(path) {
                photo
            } else {
                card
            }
            if let upload, let path {
                uploadStatus(upload, path: path)
            }
        }
        .quickLookPreview($previewURL)
        .fullScreenCover(isPresented: $showsDocument) {
            if let path {
                ArtiseNoteDocumentView(service: service, roomID: roomID, path: path) { showsDocument = false }
            }
        }
        .task(id: path) { await loadPhoto() }
        .confirmationDialog(ArtiseNotesL10n.text("screen_notes_upload_cancel_title"), isPresented: $showsCancelUpload, titleVisibility: .visible) {
            Button(ArtiseNotesL10n.text("screen_notes_upload_cancel"), role: .destructive) {
                guard let path else { return }
                Task { try? await service.repository.cancelUpload(roomID: roomID, path: path) }
            }
            Button(ArtiseNotesL10n.text("screen_notes_upload_keep"), role: .cancel) { }
        } message: {
            Text(String(format: ArtiseNotesL10n.text("screen_notes_upload_cancel_message"), NotesFolderEntries.fileName(path ?? target)))
        }
    }
    
    @ViewBuilder
    private var photo: some View {
        if let image {
            Button { open() } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 420, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NotesFolderEntries.fileName(path ?? target))
        } else {
            card
        }
    }
    
    private var card: some View {
        Button { open() } label: {
            HStack(spacing: 12) {
                CompoundIcon(icon)
                    .foregroundStyle(.compound.iconSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NotesFolderEntries.fileName(path ?? target))
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.compound.bodySM)
                            .foregroundStyle(.compound.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                }
            }
            .padding(12)
            .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(path == nil)
    }
    
    private var icon: KeyPath<CompoundIcons, Image> {
        NotesFolderEntries.isImage(target) ? \.image : \.files
    }
    
    private var detail: String? {
        if path == nil {
            return ArtiseNotesL10n.text("screen_notes_attachment_missing")
        }
        if failed {
            return ArtiseNotesL10n.text("screen_notes_attachment_unavailable")
        }
        return size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }
    
    private func uploadStatus(_ status: UploadStatus, path: String) -> some View {
        HStack(spacing: 8) {
            if status == .uploading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(ArtiseNotesL10n.text(Self.statusKey(status)))
                .font(.compound.bodySM)
                .foregroundStyle(status == .failed ? Color.compound.textCriticalPrimary : Color.compound.textSecondary)
            Spacer(minLength: 0)
            if status == .failed || status == .retrying {
                Button(ArtiseNotesL10n.text("screen_notes_upload_retry")) {
                    Task { try? await service.repository.retryUpload(roomID: roomID, path: path) }
                }
                .font(.compound.bodySMSemibold)
            }
            Button(ArtiseNotesL10n.text("screen_notes_upload_cancel")) { showsCancelUpload = true }
                .font(.compound.bodySMSemibold)
        }
    }
    
    private static func statusKey(_ status: UploadStatus) -> String {
        switch status {
        case .waiting: "screen_notes_upload_waiting"
        case .uploading: "screen_notes_upload_uploading"
        case .retrying: "screen_notes_upload_retrying"
        case .failed: "screen_notes_upload_failed"
        }
    }
    
    private func loadPhoto() async {
        guard let path, NotesFolderEntries.isImage(path) else { return }
        let repository = service.repository
        let url = try? await repository.attachment(roomID: roomID, path: path)
        guard let url else {
            failed = true
            return
        }
        image = await Task.detached { UIImage(contentsOfFile: url.path)?.preparingForDisplay() }.value
        failed = image == nil
    }
    
    /// Opens a document in its viewer, anything else in Quick Look, downloading it first if it isn't on the phone yet.
    private func open() {
        guard let path, !isLoading else { return }
        if ArtiseNoteDocument.route(roomID: roomID, path: path) != nil {
            showsDocument = true
            return
        }
        isLoading = true
        failed = false
        Task {
            defer { isLoading = false }
            do {
                previewURL = try await service.repository.attachment(roomID: roomID, path: path)
            } catch {
                failed = true
            }
        }
    }
}
