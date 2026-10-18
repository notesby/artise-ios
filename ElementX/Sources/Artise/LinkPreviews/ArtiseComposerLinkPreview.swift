//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseLinkPreview
import Compound
import SwiftUI

/// The preview of the link being typed in a chat's composer, as on Android: it appears above the message field once
/// the page is read, and its X sends the link without it. Replies, edits and threads go without a preview.
@Observable
final class ArtiseComposerLinkPreview {
    enum State: Equatable {
        case none
        case loading(url: String)
        case ready(DraftLinkPreview)
    }
    
    private(set) var state = State.none
    
    @ObservationIgnored private let roomProxy: JoinedRoomProxyProtocol
    @ObservationIgnored private var url: String?
    /// The link whose preview was closed: it isn't shown again while the message has that link.
    @ObservationIgnored private var dismissedURL: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    
    init(roomProxy: JoinedRoomProxyProtocol) {
        self.roomProxy = roomProxy
    }
    
    /// The message field changed; `text` is empty when the composer can't send a preview (replies, edits, formatting).
    func update(text: String) {
        let url = ArtiseLinkPreviews.shared.isAvailable ? LinkFinder.firstLink(text) : nil
        guard url != self.url else { return }
        self.url = url
        task?.cancel()
        // After sending, the field empties: the preview stays registered until the message picks it up.
        guard let url, url != dismissedURL else {
            state = .none
            return
        }
        dismissedURL = nil
        state = .loading(url: url)
        task = Task { [weak self] in
            // Wait for the typing to settle before reading the page.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let preview = await ArtiseLinkPreviews.shared.fetch(url)
            guard !Task.isCancelled, let self else { return }
            state = preview.map(State.ready) ?? .none
            register(preview)
        }
    }
    
    /// The X: the message goes with the link only.
    func dismiss() {
        task?.cancel()
        dismissedURL = url
        state = .none
        register(nil)
    }
    
    private func register(_ preview: DraftLinkPreview?) {
        let roomProxy = roomProxy
        ArtiseLinkPreviews.shared.setPending(preview, timeline: roomProxy.timeline as AnyObject) {
            roomProxy.infoPublisher.value.isEncrypted
        }
    }
}

/// The card above the message field.
struct ArtiseComposerLinkPreviewView: View {
    let model: ArtiseComposerLinkPreview
    
    var body: some View {
        switch model.state {
        case .none:
            EmptyView()
        case .loading(let url):
            card {
                ProgressView()
                    .frame(width: 20, height: 20)
                Text(DraftLinkPreview(url: url, title: nil, description: nil, siteName: nil, image: nil).siteLabel)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        case .ready(let preview):
            card {
                if let data = preview.image?.data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                ArtiseLinkPreviewTexts(siteLabel: preview.siteLabel, title: preview.title, description: preview.description, descriptionLines: 1)
                Spacer(minLength: 0)
                Button { model.dismiss() } label: {
                    CompoundIcon(\.close, size: .small, relativeTo: .compound.bodyMD)
                        .foregroundStyle(.compound.iconSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.actionRemove)
            }
        }
    }
    
    private func card(@ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 8) {
            content()
        }
        .padding(8)
        .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 8)
    }
}

/// The site, title and description, as on Android's cards.
struct ArtiseLinkPreviewTexts: View {
    let siteLabel: String
    let title: String?
    let description: String?
    let descriptionLines: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(siteLabel)
                .font(.compound.bodySMSemibold)
                .foregroundStyle(.compound.textSecondary)
                .lineLimit(1)
            if let title {
                Text(title)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(2)
            }
            if let description {
                Text(description)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(descriptionLines)
            }
        }
        .multilineTextAlignment(.leading)
    }
}
