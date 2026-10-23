//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// A small picture of a photo or a PDF's first page in a list row, from the Notes API's preview (kept on the phone
/// per file version); the file's icon until it's there, or when the file has no preview.
struct NotePreviewThumbnail: View {
    static let side: CGFloat = 40
    
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    /// The file's version: a changed file gets its picture again.
    let version: String
    let icon: KeyPath<CompoundIcons, Image>
    /// A chart or dashboard is drawn by the server, asked for every time it shows.
    var kind: NoteDocumentKind?
    
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            if let kind, kind.isDrawn {
                NoteDrawingImage(service: service, roomID: roomID, path: path, size: 128, fill: true, icon: icon, iconSize: 20)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                CompoundIcon(icon)
                    .foregroundStyle(.compound.iconSecondary)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .background(.compound.bgSubtleSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: version) { await load() }
    }
    
    private func load() async {
        guard kind?.isDrawn != true else { return }
        let repository = service.repository
        guard case .image(let url)? = try? await repository.preview(roomID: roomID, path: path, size: 128) else { return }
        image = await Task.detached { UIImage(contentsOfFile: url.path)?.preparingForDisplay() }.value
    }
}
