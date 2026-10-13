//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

/// The `m.sticker` event other Matrix apps read: text, picture, and its size so they can lay it out before it loads.
public enum StickerMessage {
    public static let eventType = "m.sticker"
    
    /// What apps that can't draw stickers show instead, and what screen readers say, for stickers made or pasted here.
    public static let defaultDescription = "Sticker"
    
    public static func content(_ sticker: Sticker, mxcURL: String) -> String {
        var info: [String: Any] = ["w": sticker.width, "h": sticker.height, "mimetype": sticker.mimeType]
        if sticker.size > 0 {
            info["size"] = sticker.size
        }
        return ImagePack.serialize(["body": sticker.description, "url": mxcURL, "info": info])
    }
}

/// Pictures pasted from a sticker keyboard: small WebP, PNG and GIF pictures go as stickers; photos and big files
/// go the usual way, as pictures.
public enum KeyboardStickers {
    public static let maxBytes = 1024 * 1024
    
    private static let types: Set = ["image/webp", "image/png", "image/gif"]
    
    public static func isStickerType(_ mimeType: String?) -> Bool {
        mimeType.map { types.contains($0.lowercased()) } ?? false
    }
    
    public static func isStickerSize(_ size: Int) -> Bool {
        (1...maxBytes).contains(size)
    }
}
