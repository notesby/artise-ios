//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseStickers
import Foundation
import Testing

struct StickerFormatsTests {
    private let uploaded = Sticker(id: "", description: "Sticker", source: .uploaded(mxcURL: "mxc://artise.co/abc"),
                                   width: 300, height: 200, mimeType: "image/webp", size: 1234)
    
    /// A new pack gets the sticker and a name; the image is marked as a sticker for other apps.
    @Test
    func addingToAnEmptyPack() throws {
        let content = try ImagePack.adding(uploaded, as: "sticker_1", to: nil, packName: "My stickers")
        #expect(ImagePack.stickers(content) == [uploaded.with(id: "sticker_1")])
        let root = ImagePack.parse(content)
        #expect((root["pack"] as? [String: Any])?["display_name"] as? String == "My stickers")
        let image = try #require((root["images"] as? [String: Any])?["sticker_1"] as? [String: Any])
        #expect(image["usage"] as? [String] == ["sticker"])
        #expect(content.contains("\"mxc://artise.co/abc\""))
    }
    
    /// Custom emojis another app keeps in the same pack are left alone, and aren't shown as stickers.
    @Test
    func otherAppsEmojisAreKeptAndNotShown() throws {
        let fromFluffyChat = #"{"images": {"blobcat": {"url": "mxc://x/cat", "usage": ["emoticon"]}}, "pack": {"display_name": "Mine"}}"#
        let content = try ImagePack.adding(uploaded, as: "sticker_1", to: fromFluffyChat, packName: "My stickers")
        #expect(ImagePack.stickers(content).map(\.id) == ["sticker_1"])
        let root = ImagePack.parse(content)
        #expect(Set((root["images"] as? [String: Any])?.keys ?? [:].keys) == ["blobcat", "sticker_1"])
        #expect((root["pack"] as? [String: Any])?["display_name"] as? String == "Mine")
        // An image without "usage" is both an emoji and a sticker.
        #expect(ImagePack.stickers(#"{"images": {"both": {"url": "mxc://x/y"}}}"#).map(\.id) == ["both"])
    }
    
    /// Removing takes out just that sticker; new names skip the ones taken; stickers keep the order they were added.
    @Test
    func removingAndNaming() throws {
        var content: String? = nil
        for number in 1...10 {
            content = try ImagePack.adding(uploaded, as: "sticker_\(number)", to: content, packName: "P")
        }
        #expect(ImagePack.freeShortcode(content) == "sticker_11")
        #expect(ImagePack.stickers(content).map(\.id).prefix(3) == ["sticker_1", "sticker_2", "sticker_3"])
        let fewer = ImagePack.removing("sticker_1", from: content)
        #expect(ImagePack.stickers(fewer).count == 9)
        #expect(ImagePack.freeShortcode(fewer) == "sticker_1")
        #expect(ImagePack.stickers("not json").isEmpty)
    }
    
    /// A sticker on the app only (the starter pack) can't go in the pack before it's uploaded.
    @Test
    func onlyUploadedStickersGoInThePack() {
        let starter = Sticker(id: "starter:cat", description: "Cat", source: .starter(fileName: "cat.webp"),
                              width: 256, height: 256, mimeType: "image/webp", size: 3)
        #expect(throws: StickerError.notUploaded) {
            try ImagePack.adding(starter, as: "sticker_1", to: nil, packName: "P")
        }
    }
    
    /// The message other apps read: text, picture, and its size so they can lay it out before it loads.
    @Test
    func stickerMessage() throws {
        let content = ImagePack.parse(StickerMessage.content(uploaded, mxcURL: "mxc://artise.co/abc"))
        #expect(content["body"] as? String == "Sticker")
        #expect(content["url"] as? String == "mxc://artise.co/abc")
        let info = try #require(content["info"] as? [String: Any])
        #expect(ImagePack.integer(info["w"]) == 300)
        #expect(ImagePack.integer(info["size"]) == 1234)
        #expect(info["mimetype"] as? String == "image/webp")
        // An unknown size is left out rather than sent as 0.
        let unknownSize = Sticker(id: "", description: "S", source: .uploaded(mxcURL: "mxc://a/b"), width: 1, height: 1, mimeType: "image/png", size: 0)
        #expect((ImagePack.parse(StickerMessage.content(unknownSize, mxcURL: "mxc://a/b"))["info"] as? [String: Any])?["size"] == nil)
    }
    
    /// The starter pack speaks the app's language: Spanish names in Spanish, English otherwise.
    @Test
    func starterPackNames() throws {
        let manifest = Data(#"{"stickers": [{"id": "coffee", "en": "Hot beverage", "es": "Café", "w": 256, "h": 256, "size": 5000}]}"#.utf8)
        #expect(StarterPack.stickers(manifest: manifest, language: "es").first?.description == "Café")
        let sticker = try #require(StarterPack.stickers(manifest: manifest, language: "fr").first)
        #expect(sticker.description == "Hot beverage")
        #expect(sticker.id == "starter:coffee")
        #expect(sticker.source == .starter(fileName: "coffee.webp"))
    }
    
    /// The app's starter pack has all 48 stickers, each with its picture.
    @Test
    func bundledStarterPack() throws {
        let stickers = StarterPack.bundled.stickers(language: "en")
        #expect(stickers.count == 48)
        for sticker in stickers {
            guard case let .starter(fileName) = sticker.source else {
                Issue.record("\(sticker.id) isn't a starter sticker")
                continue
            }
            #expect(try StarterPack.bundled.data(for: fileName).count == sticker.size)
        }
    }
    
    /// A cut-out is trimmed to what's visible, with a little air; nothing visible means nothing was cut out.
    @Test
    func trimmingACutOut() {
        let box = StickerGeometry.visibleBox(width: 10, height: 10, padding: 1) { x, y in (3...5).contains(x) && (4...6).contains(y) ? 255 : 0 }
        #expect(box == PixelBox(left: 2, top: 3, right: 7, bottom: 8))
        #expect(StickerGeometry.visibleBox(width: 4, height: 4, padding: 1) { _, _ in 5 } == nil)
        #expect(StickerGeometry.centerSquare(width: 300, height: 200) == PixelBox(left: 50, top: 0, right: 250, bottom: 200))
    }
    
    /// Stickers are at most 512 px, keep their shape, and small ones aren't blown up.
    @Test
    func stickerSize() {
        #expect(StickerGeometry.fit(width: 1024, height: 768) == (512, 384))
        #expect(StickerGeometry.fit(width: 200, height: 100) == (200, 100))
    }
    
    /// From a keyboard, small WebP, PNG and GIF pictures are stickers; photos and big files aren't.
    @Test
    func keyboardStickers() {
        #expect(KeyboardStickers.isStickerType("image/webp"))
        #expect(KeyboardStickers.isStickerType("image/GIF"))
        #expect(!KeyboardStickers.isStickerType("image/jpeg"))
        #expect(!KeyboardStickers.isStickerType(nil))
        #expect(KeyboardStickers.isStickerSize(500_000))
        #expect(!KeyboardStickers.isStickerSize(3_000_000))
        #expect(!KeyboardStickers.isStickerSize(0))
    }
}
