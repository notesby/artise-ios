//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseStickers
import Compound
import PhotosUI
import SwiftUI

/// The sticker picker, as in the Android app: the person's own stickers ("Mine", with + to make one from a photo)
/// and the starter pack. A tap sends the sticker; long press removes one of your own.
struct StickerPickerScreen: View {
    @Bindable var model: StickerPickerModel
    
    @State private var photo: PhotosPickerItem?
    
    var body: some View {
        VStack(spacing: 0) {
            Picker(ArtiseStickersL10n.text("screen_stickers_open"), selection: $model.tab) {
                Text(ArtiseStickersL10n.text("screen_stickers_mine")).tag(StickerPickerModel.Tab.mine)
                Text(ArtiseStickersL10n.text("screen_stickers_starter")).tag(StickerPickerModel.Tab.starter)
            }
            .pickerStyle(.segmented)
            .padding(16)
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    if model.tab == .mine {
                        makeTile
                    }
                    ForEach(model.tab == .mine ? model.mine : model.starter) { sticker in
                        tile(sticker)
                    }
                }
                .padding(.horizontal, 16)
                
                if let footer {
                    Text(footer)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(16)
                }
            }
        }
        .background(.compound.bgCanvasDefault)
        .task { await model.load() }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            model.make(from: item)
        }
        .sheet(item: $model.made) { made in
            MadeStickerSheet(made: made, model: model)
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled(model.isSavingMade)
        }
        .alert(ArtiseStickersL10n.text("screen_stickers_remove_title"), isPresented: isRemoving, presenting: model.removing) { _ in
            Button(ArtiseStickersL10n.text("screen_stickers_remove"), role: .destructive) { model.confirmRemove() }
            Button(L10n.actionCancel, role: .cancel) { }
        } message: { _ in
            Text(ArtiseStickersL10n.text("screen_stickers_remove_message"))
        }
        .alert(L10n.commonError, isPresented: hasProblem, presenting: model.problem) { _ in
            Button(L10n.actionOk) { }
        } message: { problem in
            Text(ArtiseStickersL10n.text(problem.messageKey))
        }
    }
    
    private var footer: String? {
        switch model.tab {
        case .mine: model.mine.isEmpty ? ArtiseStickersL10n.text("screen_stickers_empty") : nil
        case .starter: ArtiseStickersL10n.text("screen_stickers_starter_credit")
        }
    }
    
    private var makeTile: some View {
        PhotosPicker(selection: $photo, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.compound.bgSubtleSecondary)
                if model.isMaking {
                    ProgressView()
                } else {
                    CompoundIcon(\.plus)
                        .foregroundStyle(.compound.iconPrimary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .disabled(model.isMaking)
        .accessibilityLabel(ArtiseStickersL10n.text("screen_stickers_make"))
    }
    
    private func tile(_ sticker: Sticker) -> some View {
        Button { model.send(sticker) } label: {
            StickerImage(sticker: sticker, mediaProvider: model.service.mediaProvider)
                .padding(4)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if model.sendingID == sticker.id {
                        ProgressView()
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .opacity(model.sendingID != nil && model.sendingID != sticker.id ? 0.4 : 1)
        .accessibilityLabel(sticker.description)
        .contextMenu {
            if model.tab == .mine {
                Button(role: .destructive) {
                    model.removing = sticker
                } label: {
                    Label(ArtiseStickersL10n.text("screen_stickers_remove"), icon: \.delete)
                }
            }
        }
    }
    
    private var isRemoving: Binding<Bool> {
        Binding { model.removing != nil } set: {
            if !$0 {
                model.removing = nil
            }
        }
    }
    
    private var hasProblem: Binding<Bool> {
        // While the made sticker's sheet is up, it shows the problem instead.
        Binding { model.problem != nil && model.made == nil } set: {
            if !$0 {
                model.problem = nil
            }
        }
    }
}

/// The sticker just made, on a sheet of its own: save it, save and send it, or drop it.
private struct MadeStickerSheet: View {
    let made: MadeSticker
    @Bindable var model: StickerPickerModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(ArtiseStickersL10n.text("screen_stickers_preview_title"))
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                
                Group {
                    if let image = UIImage(data: made.picture.data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    }
                }
                .frame(width: 200, height: 200)
                .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel(ArtiseStickersL10n.text("screen_stickers_preview_title"))
                
                if !made.isCutOut {
                    Text(ArtiseStickersL10n.text("screen_stickers_not_cut_out"))
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                Button { model.saveMade(andSend: true) } label: {
                    HStack(spacing: 8) {
                        if model.isSavingMade {
                            ProgressView()
                        }
                        Text(ArtiseStickersL10n.text("screen_stickers_save_and_send"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.compound(.primary))
                
                Button(ArtiseStickersL10n.text("screen_stickers_save")) { model.saveMade(andSend: false) }
                    .buttonStyle(.compound(.secondary))
                
                Button(L10n.actionCancel) { model.made = nil }
                    .buttonStyle(.compound(.tertiary))
            }
            .disabled(model.isSavingMade)
            .padding(16)
        }
        .background(.compound.bgCanvasDefault)
        .alert(L10n.commonError, isPresented: hasProblem, presenting: model.problem) { _ in
            Button(L10n.actionOk) { }
        } message: { problem in
            Text(ArtiseStickersL10n.text(problem.messageKey))
        }
    }
    
    private var hasProblem: Binding<Bool> {
        Binding { model.problem != nil } set: {
            if !$0 {
                model.problem = nil
            }
        }
    }
}

/// A sticker's picture: from the server (the person's own) or from the app (the starter pack).
private struct StickerImage: View {
    let sticker: Sticker
    let mediaProvider: MediaProviderProtocol
    
    var body: some View {
        switch sticker.source {
        case .uploaded(let mxcURL):
            if let url = URL(string: mxcURL), let source = try? MediaSourceProxy(url: url, mimeType: sticker.mimeType) {
                LoadableImage(mediaSource: source, mediaProvider: mediaProvider, transformer: { $0.scaledToFit() }) {
                    ProgressView()
                }
            }
        case .starter(let fileName):
            if let path = StarterPack.bundled.url(for: fileName)?.path(), let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}

/// What the picker shows and does; the same steps as the Android app's presenter.
@Observable
final class StickerPickerModel {
    enum Tab: Hashable {
        case mine
        case starter
    }
    
    enum Problem {
        case sendFailed
        case makeFailed
        case saveFailed
        case removeFailed
        
        var messageKey: String {
            switch self {
            case .sendFailed: "screen_stickers_send_failed"
            case .makeFailed: "screen_stickers_make_failed"
            case .saveFailed: "screen_stickers_save_failed"
            case .removeFailed: "screen_stickers_remove_failed"
            }
        }
    }
    
    let service: ArtiseStickerService
    let roomID: String
    let starter: [Sticker]
    
    private(set) var mine: [Sticker] = []
    /// The sticker being sent right now: it shows a spinner, and other taps wait.
    private(set) var sendingID: String?
    private(set) var isMaking = false
    var made: MadeSticker?
    private(set) var isSavingMade = false
    var removing: Sticker?
    var problem: Problem?
    
    /// The person's own stickers first, once they have some.
    var tab: Tab {
        get { chosenTab ?? (mine.isEmpty ? .starter : .mine) }
        set { chosenTab = newValue }
    }
    
    private var chosenTab: Tab?
    private let onSent: () -> Void
    
    init(service: ArtiseStickerService, roomID: String, onSent: @escaping () -> Void) {
        self.service = service
        self.roomID = roomID
        self.onSent = onSent
        starter = service.repository.starterStickers(language: Self.language)
    }
    
    /// Spanish names in Spanish, English otherwise, following the language the app is shown in.
    private static var language: String {
        String(Bundle.main.preferredLocalizations.first?.prefix(2) ?? "en")
    }
    
    func load() async {
        mine = await service.repository.mine
        do {
            mine = try await service.repository.refresh()
        } catch {
            MXLog.error("Stickers: couldn't read the account's stickers: \(error)")
        }
    }
    
    func send(_ sticker: Sticker) {
        guard sendingID == nil else { return }
        sendingID = sticker.id
        Task {
            do {
                try await service.send(sticker, roomID: roomID)
                onSent()
            } catch {
                MXLog.error("Stickers: couldn't send: \(error)")
                problem = .sendFailed
            }
            sendingID = nil
        }
    }
    
    func make(from item: PhotosPickerItem) {
        guard !isMaking else { return }
        isMaking = true
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw StickerMakerError.unreadable }
                made = try await StickerMaker.make(from: data)
            } catch {
                MXLog.error("Stickers: couldn't make a sticker: \(error)")
                problem = .makeFailed
            }
            isMaking = false
        }
    }
    
    /// Keeps the sticker just made, and sends it too when `andSend`.
    func saveMade(andSend: Bool) {
        guard let made, !isSavingMade else { return }
        isSavingMade = true
        Task {
            do {
                let saved = try await service.repository.addToMine(made.picture, description: StickerMessage.defaultDescription)
                mine = await service.repository.mine
                chosenTab = .mine
                self.made = nil
                if andSend {
                    send(saved)
                }
            } catch {
                MXLog.error("Stickers: couldn't save a sticker: \(error)")
                problem = .saveFailed
            }
            isSavingMade = false
        }
    }
    
    func confirmRemove() {
        guard let sticker = removing else { return }
        removing = nil
        Task {
            do {
                try await service.repository.remove(sticker)
            } catch {
                MXLog.error("Stickers: couldn't remove a sticker: \(error)")
                problem = .removeFailed
            }
            mine = await service.repository.mine
        }
    }
}

/// The stickers texts, from the `ArtiseStickers` string table (imported from the Android app, same keys).
enum ArtiseStickersL10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "ArtiseStickers", bundle: .main, comment: "")
    }
}
