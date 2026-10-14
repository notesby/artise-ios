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
    /// A picture shared with "Artise sticker" while the app was still starting, shown once the session is ready.
    private var pendingShare: PendingShare?
    
    /// Called when an account's session is ready, and with `nil` when it's gone.
    func configure(with userSession: UserSessionProtocol?) {
        service = userSession.flatMap(ArtiseStickerService.init)
        if service != nil, let pending = pendingShare {
            pendingShare = nil
            presentAddSticker(pending.picture)
        }
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
    
    // MARK: - Saving others' stickers
    
    /// "Save to my stickers" is offered for stickers whose picture is plain on the server, which is how Matrix apps
    /// send them; an encrypted picture can't go in a pack other devices read.
    func canSave(_ item: StickerRoomTimelineItem) -> Bool {
        service != nil && !item.imageInfo.source.underlyingSource.toJson().contains("\"key\"")
    }
    
    /// Keeps a sticker someone sent in the person's own stickers, reusing its picture on the server. Returns what
    /// to tell the person.
    func save(_ item: StickerRoomTimelineItem) async -> String {
        guard let service, let url = item.imageInfo.source.url else {
            return ArtiseStickersL10n.text("screen_stickers_save_received_failed")
        }
        let info = item.imageInfo
        let sticker = Sticker(id: "",
                              description: item.body,
                              source: .uploaded(mxcURL: url.absoluteString),
                              width: Int(info.size?.width ?? 256),
                              height: Int(info.size?.height ?? 256),
                              mimeType: info.mimeType ?? "image/png",
                              size: Int(info.fileSize ?? 0))
        do {
            _ = try await service.repository.addUploaded(sticker)
            return ArtiseStickersL10n.text("screen_stickers_saved")
        } catch {
            MXLog.error("Stickers: couldn't save a received sticker: \(error)")
            return ArtiseStickersL10n.text("screen_stickers_save_received_failed")
        }
    }
    
    // MARK: - Stickers from other apps
    
    /// The "Artise sticker" share extension opens `<bundle ID>:/artise-sticker?file=<name>`, with the picture in the
    /// app group's `ArtiseStickers` folder.
    static let shareURLPath = "artise-sticker"
    static let shareFolder = "ArtiseStickers"
    
    /// Shows a picture shared with "Artise sticker" and offers to save it to the person's stickers. Returns `false`
    /// for any other URL.
    func handleURL(_ url: URL) -> Bool {
        guard url.scheme == InfoPlistReader.main.baseBundleIdentifier,
              url.pathComponents.last == Self.shareURLPath else {
            return false
        }
        let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "file" }?.value
        let picture = name.flatMap(Self.takeSharedPicture)
        if service != nil {
            presentAddSticker(picture)
        } else {
            // Opened from the share sheet, the app may still be restoring the session: wait for it a little.
            pendingShare = PendingShare(picture: picture)
            Task {
                try? await Task.sleep(for: .seconds(10))
                if let pending = pendingShare {
                    pendingShare = nil
                    presentAddSticker(pending.picture)
                }
            }
        }
        return true
    }
    
    private func presentAddSticker(_ picture: Data?) {
        guard let presenter = UIViewController.artiseTopViewController() else { return }
        weak var host: UIViewController?
        let model = AddStickerModel(service: service, picture: picture) {
            host?.dismiss(animated: true)
        }
        let controller = UIHostingController(rootView: AddStickerScreen(model: model))
        controller.sheetPresentationController?.detents = [.medium(), .large()]
        host = controller
        presenter.present(controller, animated: true)
    }
    
    /// `picture` is `nil` when the shared file couldn't be read.
    private struct PendingShare {
        let picture: Data?
    }
    
    /// The shared picture, taken out of the app group so it doesn't pile up there.
    private static func takeSharedPicture(named name: String) -> Data? {
        guard !name.contains("/"), !name.hasPrefix(".") else { return nil }
        let file = URL.appGroupContainerDirectory.appending(path: shareFolder).appending(path: name)
        defer { try? FileManager.default.removeItem(at: file) }
        return try? Data(contentsOf: file)
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
