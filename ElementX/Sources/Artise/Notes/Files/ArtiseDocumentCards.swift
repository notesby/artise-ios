//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// The documents Ari's turn made or changed, as cards under its message: a preview of each and what happened to it,
/// a tap away from reading it in the chat's notes. A workspace without notes shows the message as plain text.
struct ArtiseDocumentCardsView: View {
    static let maxWidth: CGFloat = 320
    
    let roomID: String
    let cards: [DocumentCard]
    
    var body: some View {
        if let service = ArtiseNotes.shared.service {
            VStack(spacing: 8) {
                ForEach(cards, id: \.path) { card in
                    ArtiseDocumentCard(service: service, roomID: roomID, card: card)
                }
            }
            .frame(maxWidth: Self.maxWidth)
        }
    }
}

/// One document: its first page or first lines on top, then its icon, title, what happened to it, and "Draft".
struct ArtiseDocumentCard: View {
    static let previewHeight: CGFloat = 150
    
    let service: ArtiseNotesService
    let roomID: String
    let card: DocumentCard
    
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var text: String?
    
    var body: some View {
        Button {
            ArtiseNotes.shared.openDocument(roomID: roomID, path: card.path)
        } label: {
            VStack(spacing: 0) {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.previewHeight, alignment: .top)
                    .clipped()
                    .background(.compound.bgSubtleSecondary)
                    .allowsHitTesting(false)
                details
                    .padding(12)
            }
            .background(.compound.bgCanvasDefault)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.compound.borderInteractiveSecondary, lineWidth: 1 / displayScale)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: ArtiseNotesL10n.text("a11y_notes_card_open"), card.title))
        .accessibilityAddTraits(.isButton)
        .task(id: card.version ?? card.path) { await load() }
    }
    
    @ViewBuilder
    private var preview: some View {
        if let image {
            // The start of the page: filled, from the top.
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: Self.previewHeight, alignment: .top)
        } else if let text, card.kind == .table {
            Text(text)
                .font(.compound.bodySM.monospaced())
                .foregroundStyle(.compound.textPrimary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let text {
            // The note's first lines as they read: no header, no Markdown marks.
            NoteMarkdownView(document: NoteDocument(markdown: text), onLink: { _ in }, onToggle: nil) { _ in AnyView(EmptyView()) }
                .dynamicTypeSize(.xSmall)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            CompoundIcon(ArtiseNoteDocument.icon(card.kind), size: .custom(40), relativeTo: .compound.headingLGBold)
                .foregroundStyle(.compound.iconSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var details: some View {
        HStack(spacing: 10) {
            CompoundIcon(ArtiseNoteDocument.icon(card.kind))
                .foregroundStyle(.compound.iconSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(1)
                if let change = card.change {
                    Text(ArtiseNotesL10n.text(change == .created ? "screen_notes_card_created" : "screen_notes_card_changed"))
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if card.isDraft {
                Text(ArtiseNotesL10n.text("screen_notes_card_draft"))
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.compound.bgSubtleSecondary, in: Capsule())
            }
        }
    }
    
    /// The server's preview (512 px, kept per version); a kind it has none for keeps its icon.
    private func load() async {
        guard card.kind != .other,
              let preview = try? await service.repository.preview(roomID: roomID, path: card.path, size: 512, version: card.version) else { return }
        switch preview {
        case .image(let url):
            image = await Task.detached { UIImage(contentsOfFile: url.path)?.preparingForDisplay() }.value
        case .text(let lines):
            text = lines
        }
    }
}
