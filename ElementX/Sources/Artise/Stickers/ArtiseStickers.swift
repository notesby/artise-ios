//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseStickers
import MatrixRustSDK
import SwiftUI

/// Stickers for the signed-in account, and the one place the composer opens them from.
///
/// Upstream screens call `ArtiseStickers.shared` once each (the sticker button, pasted stickers), so the upstream
/// changes stay a few lines.
@MainActor
final class ArtiseStickers {
    static let shared = ArtiseStickers()
    
    private(set) var service: ArtiseStickerService?
    
    /// Called when an account's session is ready, and with `nil` when it's gone.
    func configure(with userSession: UserSessionProtocol?) {
        service = userSession.flatMap(ArtiseStickerService.init)
    }
    
    /// Opens the sticker picker for a chat; a tapped sticker is sent there and the picker closes.
    func openPicker(roomID: String) {
        guard let service, let presenter = UIViewController.artiseTopViewController() else {
            MXLog.error("Artise stickers can't open right now")
            return
        }
        weak var host: UIViewController?
        let model = StickerPickerModel(service: service, roomID: roomID) {
            host?.dismiss(animated: true)
        }
        let controller = UIHostingController(rootView: StickerPickerScreen(model: model))
        controller.modalPresentationStyle = .pageSheet
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        controller.sheetPresentationController?.prefersGrabberVisible = true
        host = controller
        presenter.present(controller, animated: true)
    }
    
    /// Sends a picture pasted from a sticker keyboard as a sticker. Returns `false` when it isn't one or it couldn't
    /// be sent, so it goes the usual way, as a picture with the usual retry and errors.
    func sendKeyboardSticker(_ providers: [NSItemProvider], roomID: String) async -> Bool {
        guard let service, let picture = await StickerMaker.keyboardSticker(from: providers) else { return false }
        do {
            try await service.send(picture, roomID: roomID)
            return true
        } catch {
            MXLog.error("Stickers: couldn't send a keyboard sticker, sending it as a picture: \(error)")
            return false
        }
    }
}

/// One account's stickers: its pack, the starter pack, and sending to a chat.
@MainActor
final class ArtiseStickerService {
    let repository: StickerRepository
    let mediaProvider: MediaProviderProtocol
    private let account: SDKStickerAccount
    private let clientProxy: ClientProxyProtocol
    
    init?(userSession: UserSessionProtocol) {
        guard let client = (userSession.clientProxy as? ClientProxy)?.client else {
            MXLog.error("Artise stickers need the SDK client")
            return nil
        }
        account = SDKStickerAccount(client: client)
        repository = StickerRepository(account: account)
        mediaProvider = userSession.mediaProvider
        clientProxy = userSession.clientProxy
    }
    
    /// Sends a sticker as an `m.sticker`, encrypted in encrypted chats; a starter sticker is uploaded first if needed.
    func send(_ sticker: Sticker, roomID: String) async throws {
        let url = try await repository.mxcURL(for: sticker)
        try await room(roomID).sendRaw(eventType: StickerMessage.eventType, content: StickerMessage.content(sticker, mxcURL: url))
    }
    
    /// Uploads a picture and sends it as a sticker, without keeping it in the person's stickers.
    func send(_ picture: StickerPicture, roomID: String) async throws {
        let room = try await room(roomID)
        let url = try await account.upload(data: picture.data, mimeType: picture.mimeType)
        let sticker = Sticker(id: "", description: StickerMessage.defaultDescription, source: .uploaded(mxcURL: url),
                              width: picture.width, height: picture.height, mimeType: picture.mimeType, size: picture.data.count)
        try await room.sendRaw(eventType: StickerMessage.eventType, content: StickerMessage.content(sticker, mxcURL: url))
    }
    
    private func room(_ roomID: String) async throws(ArtiseStickerServiceError) -> any RoomProtocol {
        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(roomID),
              let room = (roomProxy as? JoinedRoomProxy)?.room else {
            throw .roomNotFound
        }
        return room
    }
}

enum ArtiseStickerServiceError: Error {
    case roomNotFound
}

/// The account's data and media repository, through the Rust SDK.
nonisolated struct SDKStickerAccount: StickerAccount {
    let client: any ClientProtocol
    
    func accountData(type: String) async throws -> String? {
        try await client.accountData(eventType: type)
    }
    
    func setAccountData(type: String, content: String) async throws {
        try await client.setAccountData(eventType: type, content: content)
    }
    
    func upload(data: Data, mimeType: String) async throws -> String {
        try await client.uploadMedia(mimeType: mimeType, data: data, progressWatcher: nil)
    }
}

extension UIViewController {
    /// The screen on top of the main window, which Artise's screens are presented over.
    static func artiseTopViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var top = windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
