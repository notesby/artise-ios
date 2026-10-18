//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Compound
import SwiftUI

/// A received message's link preview, under its text: the picture that came with it, then the site, title and
/// description. Tapping it opens the link. Nothing is fetched from the website.
struct ArtiseLinkPreviewCard: View {
    let linkPreview: ArtiseMessageLinkPreview
    
    @Environment(\.timelineContext) private var context
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        Button {
            if let url = URL(string: linkPreview.preview.url) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let source = linkPreview.imageSource {
                    LoadableImage(mediaSource: source, mediaProvider: context?.mediaProvider, transformer: { $0.scaledToFill() }) {
                        Color.compound.bgSubtleSecondary
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: imageHeight)
                    .clipped()
                }
                ArtiseLinkPreviewTexts(siteLabel: linkPreview.preview.siteLabel,
                                       title: linkPreview.preview.title,
                                       description: linkPreview.preview.description,
                                       descriptionLines: 3)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.compound.bgCanvasDefault.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.compound.borderInteractiveSecondary, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: TimelineMediaFrame.maxLinkPreviewWidth)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
    
    /// The picture's own shape, kept between a wide banner and a square.
    private var imageHeight: CGFloat {
        let width = TimelineMediaFrame.maxLinkPreviewWidth
        guard let image = linkPreview.preview.image, let imageWidth = image.width, let imageHeight = image.height, imageWidth > 0 else {
            return width / 1.91
        }
        return min(width, max(width / 2.5, width * CGFloat(imageHeight) / CGFloat(imageWidth)))
    }
}
