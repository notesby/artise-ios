//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import Foundation

/// What stickers need from the signed-in account: its account data and the media repository.
public protocol StickerAccount: Sendable {
    func accountData(type: String) async throws -> String?
    func setAccountData(type: String, content: String) async throws
    /// Uploads a picture and returns its `mxc://` URL.
    func upload(data: Data, mimeType: String) async throws -> String
}

/// The person's stickers, kept in their account so every device has them, and the starter pack.
public actor StickerRepository {
    /// What the person's own pack is called in other apps.
    static let packName = "My stickers"
    /// Where starter stickers this account already uploaded are remembered, so they upload once (shared with Android).
    static let uploadsEventType = "co.artise.sticker_uploads"
    /// How long what was just written is trusted over the SDK's store, which only catches up with the next sync.
    static let writeTrust: TimeInterval = 30
    
    public private(set) var mine: [Sticker] = []
    
    private let account: StickerAccount
    private let starterPack: StarterPack
    // Reading and writing the pack happen one at a time, so two stickers saved together both stay.
    private let packLock = AsyncLock()
    private let now: @Sendable () -> Date
    private var written: [String: (content: String, at: Date)] = [:]
    
    public init(account: StickerAccount, starterPack: StarterPack = .bundled, now: @escaping @Sendable () -> Date = Date.init) {
        self.account = account
        self.starterPack = starterPack
        self.now = now
    }
    
    /// Reads the person's stickers again, to show ones saved on another device.
    @discardableResult
    public func refresh() async throws -> [Sticker] {
        mine = try await ImagePack.stickers(read(ImagePack.userPackEventType))
        return mine
    }
    
    public nonisolated func starterStickers(language: String) -> [Sticker] {
        starterPack.stickers(language: language)
    }
    
    /// Uploads a picture made or chosen here and adds it to the person's stickers.
    public func addToMine(_ picture: StickerPicture, description: String) async throws -> Sticker {
        let url = try await account.upload(data: picture.data, mimeType: picture.mimeType)
        return try await addUploaded(Sticker(id: "",
                                             description: description,
                                             source: .uploaded(mxcURL: url),
                                             width: picture.width,
                                             height: picture.height,
                                             mimeType: picture.mimeType,
                                             size: picture.data.count))
    }
    
    /// Adds a sticker whose picture is on the server already (one someone sent).
    public func addUploaded(_ sticker: Sticker) async throws -> Sticker {
        try await packLock.withLock {
            let content = try await read(ImagePack.userPackEventType)
            let shortcode = ImagePack.freeShortcode(content)
            let updated = try ImagePack.adding(sticker, as: shortcode, to: content, packName: Self.packName)
            try await write(ImagePack.userPackEventType, updated)
            mine = ImagePack.stickers(updated)
            return sticker.with(id: shortcode)
        }
    }
    
    /// Takes a sticker out of the person's stickers; messages already sent keep it.
    public func remove(_ sticker: Sticker) async throws {
        try await packLock.withLock {
            let content = try await read(ImagePack.userPackEventType)
            let updated = ImagePack.removing(sticker.id, from: content)
            try await write(ImagePack.userPackEventType, updated)
            mine = ImagePack.stickers(updated)
        }
    }
    
    /// The sticker's picture on the server; a starter sticker is uploaded the first time, then remembered.
    public func mxcURL(for sticker: Sticker) async throws -> String {
        switch sticker.source {
        case .uploaded(let url):
            return url
        case .starter(let fileName):
            return try await packLock.withLock {
                var uploads = try await ImagePack.parse(read(Self.uploadsEventType))
                if let url = uploads[sticker.id] as? String {
                    return url
                }
                let url = try await account.upload(data: starterPack.data(for: fileName), mimeType: sticker.mimeType)
                uploads[sticker.id] = url
                try await write(Self.uploadsEventType, ImagePack.serialize(uploads))
                return url
            }
        }
    }
    
    // MARK: - Account data
    
    /// The account data, or what this phone just wrote if the SDK's store hasn't caught up with it yet, so two
    /// stickers saved a second apart both stay.
    private func read(_ type: String) async throws -> String? {
        let stored = try await account.accountData(type: type)
        if let last = written[type], last.content != stored, now().timeIntervalSince(last.at) < Self.writeTrust {
            return last.content
        }
        written[type] = nil
        return stored
    }
    
    private func write(_ type: String, _ content: String) async throws {
        try await account.setAccountData(type: type, content: content)
        written[type] = (content, now())
    }
}
