//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The person's own stickers, kept in their account as an MSC2545 image pack, as the Android app does, so FluffyChat,
/// Cinny and Nheko read the same stickers. Other apps' custom emojis in that pack are kept as they are.
public enum ImagePack {
    public static let userPackEventType = "im.ponies.user_emotes"
    
    private static let defaultSide = 256
    
    /// The stickers in `content`; images marked only as emojis aren't stickers.
    public static func stickers(_ content: String?) -> [Sticker] {
        guard let images = parse(content)["images"] as? [String: Any] else { return [] }
        return images.keys.sorted(by: shortcodeOrder).compactMap { shortcode in
            guard let image = images[shortcode] as? [String: Any], let url = image["url"] as? String else { return nil }
            if let usage = image["usage"] as? [Any], !usage.contains(where: { $0 as? String == "sticker" }) {
                return nil
            }
            let info = image["info"] as? [String: Any]
            return Sticker(id: shortcode,
                           description: image["body"] as? String ?? shortcode,
                           source: .uploaded(mxcURL: url),
                           width: integer(info?["w"]) ?? defaultSide,
                           height: integer(info?["h"]) ?? defaultSide,
                           mimeType: info?["mimetype"] as? String ?? "image/webp",
                           size: integer(info?["size"]) ?? 0)
        }
    }
    
    /// `content` with `sticker` added under `shortcode`; the pack gets a name if it has none.
    public static func adding(_ sticker: Sticker, as shortcode: String, to content: String?, packName: String) throws(StickerError) -> String {
        guard case let .uploaded(url) = sticker.source else { throw .notUploaded }
        var root = parse(content)
        var images = root["images"] as? [String: Any] ?? [:]
        images[shortcode] = ["url": url,
                             "body": sticker.description,
                             "info": ["w": sticker.width, "h": sticker.height, "mimetype": sticker.mimeType, "size": sticker.size],
                             "usage": ["sticker"]]
        root["images"] = images
        if !(root["pack"] is [String: Any]) {
            root["pack"] = ["display_name": packName, "usage": ["sticker"]]
        }
        return serialize(root)
    }
    
    /// `content` without the image `shortcode`.
    public static func removing(_ shortcode: String, from content: String?) -> String {
        var root = parse(content)
        var images = root["images"] as? [String: Any] ?? [:]
        images[shortcode] = nil
        root["images"] = images
        return serialize(root)
    }
    
    /// A short name that isn't taken yet: "sticker_1", "sticker_2"...
    public static func freeShortcode(_ content: String?) -> String {
        let taken = (parse(content)["images"] as? [String: Any]).map { Set($0.keys) } ?? []
        var number = 1
        while taken.contains("sticker_\(number)") {
            number += 1
        }
        return "sticker_\(number)"
    }
    
    // MARK: - JSON
    
    static func parse(_ content: String?) -> [String: Any] {
        guard let data = content?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }
    
    static func serialize(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
    
    static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: number
        case let number as Double: Int(number)
        case let number as NSNumber: number.intValue
        default: nil
        }
    }
    
    /// Oldest first: "sticker_2" before "sticker_10", other apps' names in alphabetical order.
    private static func shortcodeOrder(_ first: String, _ second: String) -> Bool {
        first.localizedStandardCompare(second) == .orderedAscending
    }
}
