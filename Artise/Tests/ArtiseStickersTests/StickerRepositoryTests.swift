//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseStickers
import Foundation
import Synchronization
import Testing

struct StickerRepositoryTests {
    private let coffee = Sticker(id: "starter:coffee", description: "Café", source: .starter(fileName: "coffee.webp"),
                                 width: 256, height: 256, mimeType: "image/webp", size: 3)
    
    /// A sticker made from a photo is uploaded and kept in the account's pack, so every device has it.
    @Test
    func madeStickersAreKeptInTheAccount() async throws {
        let account = FakeStickerAccount()
        let repository = StickerRepository(account: account, starterPack: .bundled)
        let saved = try await repository.addToMine(StickerPicture(data: Data([9]), width: 300, height: 200, mimeType: "image/png"),
                                                   description: "Sticker")
        #expect(saved.id == "sticker_1")
        #expect(saved.source == .uploaded(mxcURL: "mxc://artise.co/1"))
        #expect(saved.size == 1)
        #expect(await repository.mine == [saved])
        #expect(await ImagePack.stickers(account.data[ImagePack.userPackEventType]) == [saved])
        
        try await repository.remove(saved)
        #expect(await repository.mine.isEmpty)
    }
    
    /// A starter sticker is uploaded the first time it's sent, then the same picture is reused, also on Android.
    @Test
    func starterStickersUploadOnce() async throws {
        let account = FakeStickerAccount()
        let repository = StickerRepository(account: account, starterPack: .bundled)
        #expect(try await repository.mxcURL(for: coffee) == "mxc://artise.co/1")
        #expect(try await repository.mxcURL(for: coffee) == "mxc://artise.co/1")
        #expect(await account.uploads == 1)
        #expect(await account.data[StickerRepository.uploadsEventType] == #"{"starter:coffee":"mxc://artise.co/1"}"#)
    }
    
    /// Two stickers saved at the same moment both stay: the pack is read and written one at a time.
    @Test
    func stickersSavedTogetherBothStay() async throws {
        let account = FakeStickerAccount()
        let repository = StickerRepository(account: account, starterPack: .bundled)
        let picture = StickerPicture(data: Data([1, 2]), width: 10, height: 10, mimeType: "image/png")
        async let first = repository.addToMine(picture, description: "A")
        async let second = repository.addToMine(picture, description: "B")
        let ids = try await Set([first.id, second.id])
        #expect(ids == ["sticker_1", "sticker_2"])
        #expect(await ImagePack.stickers(account.data[ImagePack.userPackEventType]).count == 2)
    }
    
    /// The SDK's store only shows a write after the next sync: a second sticker saved before then keeps the first.
    @Test
    func savesBeforeTheNextSyncKeepEachOther() async throws {
        let account = FakeStickerAccount()
        await account.delayWrites()
        let clock = TestClock()
        let repository = StickerRepository(account: account, starterPack: .bundled, now: clock.now)
        let picture = StickerPicture(data: Data([1]), width: 1, height: 1, mimeType: "image/png")
        _ = try await repository.addToMine(picture, description: "A")
        let second = try await repository.addToMine(picture, description: "B")
        #expect(second.id == "sticker_2")
        #expect(await repository.mine.map(\.description) == ["A", "B"])
        
        // Long after, the store is what counts again (another device may have changed it).
        await account.sync()
        await account.set(ImagePack.userPackEventType, #"{"images": {}}"#)
        clock.advance(by: 60)
        #expect(try await repository.refresh().isEmpty)
    }
    
    /// Stickers saved on another device show after a refresh.
    @Test
    func refreshReadsTheAccount() async throws {
        let account = FakeStickerAccount()
        await account.set(ImagePack.userPackEventType, #"{"images": {"sticker_7": {"url": "mxc://x/y", "body": "Perro"}}}"#)
        let repository = StickerRepository(account: account, starterPack: .bundled)
        try await repository.refresh()
        #expect(await repository.mine.map(\.description) == ["Perro"])
    }
    
    /// A failed save leaves the person's stickers as they were.
    @Test
    func failedSavesChangeNothing() async throws {
        let account = FakeStickerAccount()
        await account.failWrites()
        let repository = StickerRepository(account: account, starterPack: .bundled)
        let picture = StickerPicture(data: Data([1]), width: 1, height: 1, mimeType: "image/png")
        await #expect(throws: FakeStickerAccount.Failure.self) {
            try await repository.addToMine(picture, description: "Sticker")
        }
        #expect(await repository.mine.isEmpty)
    }
}

/// An account kept in memory: account data by type, and uploads numbered in order.
private actor FakeStickerAccount: StickerAccount {
    struct Failure: Error { }
    
    /// What the SDK's store shows.
    private(set) var data: [String: String] = [:]
    private(set) var uploads = 0
    private var writesFail = false
    private var writesDelayed = false
    private var unsynced: [String: String] = [:]
    
    func set(_ type: String, _ content: String) {
        data[type] = content
    }
    
    func failWrites() {
        writesFail = true
    }
    
    /// Writes reach the store at the next `sync()`, as with the SDK.
    func delayWrites() {
        writesDelayed = true
    }
    
    func sync() {
        data.merge(unsynced) { $1 }
        unsynced = [:]
    }
    
    func accountData(type: String) async throws -> String? {
        await Task.yield()
        return data[type]
    }
    
    func setAccountData(type: String, content: String) async throws {
        await Task.yield()
        if writesFail {
            throw Failure()
        }
        if writesDelayed {
            unsynced[type] = content
        } else {
            data[type] = content
        }
    }
    
    func upload(data: Data, mimeType: String) async throws -> String {
        uploads += 1
        return "mxc://artise.co/\(uploads)"
    }
}

/// A clock the test moves forward.
private final class TestClock: Sendable {
    private let time = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
    
    var now: @Sendable () -> Date {
        { self.time.withLock { $0 } }
    }
    
    func advance(by seconds: TimeInterval) {
        time.withLock { $0 += seconds }
    }
}
