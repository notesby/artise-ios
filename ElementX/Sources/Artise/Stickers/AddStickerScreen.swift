//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseStickers
import Compound
import SwiftUI

/// A picture shared with "Artise sticker" from another app, shown before it's saved to the person's stickers, as
/// on Android. Pictures with a transparent background (from sticker apps) are kept as they are; photos are cut out.
struct AddStickerScreen: View {
    let model: AddStickerModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(ArtiseStickersL10n.text("screen_stickers_add_title"))
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
                
                content
            }
            .padding(16)
        }
        .background(.compound.bgCanvasDefault)
        .task { await model.prepare() }
    }
    
    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .preparing:
            ProgressView()
                .padding(32)
        case .signedOut:
            message(ArtiseStickersL10n.text("screen_stickers_add_signed_out"))
        case .failed:
            message(ArtiseStickersL10n.text("screen_stickers_add_failed"))
        case .saved:
            message(ArtiseStickersL10n.text("screen_stickers_saved"))
        case .ready(let made, let isSaving):
            if let image = UIImage(data: made.picture.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .frame(width: 200, height: 200)
                    .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(ArtiseStickersL10n.text("screen_stickers_preview_title"))
            }
            if !made.isCutOut {
                note(ArtiseStickersL10n.text("screen_stickers_not_cut_out"), isError: false)
            }
            if model.saveFailed {
                note(ArtiseStickersL10n.text("screen_stickers_save_failed"), isError: true)
            }
            Button { model.save() } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                    }
                    Text(ArtiseStickersL10n.text("screen_stickers_save"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.compound(.primary))
            .disabled(isSaving)
            Button(L10n.actionCancel) { model.close() }
                .buttonStyle(.compound(.tertiary))
                .disabled(isSaving)
        }
    }
    
    private func message(_ text: String) -> some View {
        VStack(spacing: 16) {
            Text(text)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textPrimary)
                .multilineTextAlignment(.center)
            Button(L10n.actionClose) { model.close() }
                .buttonStyle(.compound(.primary))
        }
    }
    
    private func note(_ text: String, isError: Bool) -> some View {
        Text(text)
            .font(.compound.bodySM)
            .foregroundStyle(isError ? .compound.textCriticalPrimary : .compound.textSecondary)
            .multilineTextAlignment(.center)
    }
}

/// The steps of adding a shared picture; the same as the Android app's presenter.
@Observable
final class AddStickerModel {
    enum Step {
        case preparing
        /// Nobody is signed in on this phone.
        case signedOut
        case failed
        case ready(MadeSticker, isSaving: Bool)
        case saved
    }
    
    private(set) var step = Step.preparing
    /// The last save didn't work: say so, and let the person try again.
    private(set) var saveFailed = false
    
    private let service: ArtiseStickerService?
    private let picture: Data?
    private let onClose: () -> Void
    
    init(service: ArtiseStickerService?, picture: Data?, onClose: @escaping () -> Void) {
        self.service = service
        self.picture = picture
        self.onClose = onClose
    }
    
    func prepare() async {
        guard case .preparing = step else { return }
        guard service != nil else {
            step = .signedOut
            return
        }
        guard let picture else {
            step = .failed
            return
        }
        do {
            step = try await .ready(StickerMaker.make(from: picture), isSaving: false)
        } catch {
            MXLog.error("Stickers: couldn't make a sticker from a shared picture: \(error)")
            step = .failed
        }
    }
    
    func save() {
        guard let service, case let .ready(made, isSaving) = step, !isSaving else { return }
        step = .ready(made, isSaving: true)
        saveFailed = false
        Task {
            do {
                _ = try await service.repository.addToMine(made.picture, description: StickerMessage.defaultDescription)
                step = .saved
            } catch {
                MXLog.error("Stickers: couldn't save a shared sticker: \(error)")
                step = .ready(made, isSaving: false)
                saveFailed = true
            }
        }
    }
    
    func close() {
        onClose()
    }
}
