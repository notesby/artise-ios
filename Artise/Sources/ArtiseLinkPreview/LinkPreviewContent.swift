//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Link previews inside messages, as MSC4095 describes them (with Beeper's `com.beeper.linkpreviews` field, which
/// other apps already read): Open Graph keys for the page, and the picture as `og:image` or, in encrypted chats,
/// `beeper:image:encryption`. The same JSON as the Android app.
public enum LinkPreviewContent {
    public static let field = "com.beeper.linkpreviews"
    // MSC4095's name once it's in the spec; read too, so previews keep working when apps switch.
    static let stableField = "m.url_previews"
    
    /// The JSON object added to the message's content.
    public static func build(_ preview: DraftLinkPreview, image: UploadedImage?) -> String {
        var entry: [String: Any] = ["matched_url": preview.url, "og:url": preview.url]
        entry["og:title"] = preview.title
        entry["og:description"] = preview.description
        entry["og:site_name"] = preview.siteName
        if let image {
            entry["og:image:type"] = "image/jpeg"
            entry["og:image:width"] = image.width
            entry["og:image:height"] = image.height
            entry["matrix:image:size"] = image.size
            if let encryption = image.encryption {
                entry["beeper:image:encryption"] = encryptedFile(image.mxcURL, encryption)
            } else {
                entry["og:image"] = image.mxcURL
            }
        }
        return serialize([field: [entry]])
    }
    
    /// The first preview in an event (the whole event, or just its content) that has a link, or `nil`.
    public static func read(_ eventJSON: String) -> LinkPreview? {
        guard let data = eventJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let content = root["content"] as? [String: Any] ?? root
        guard let previews = (content[field] ?? content[stableField]) as? [Any] else { return nil }
        return previews.lazy.compactMap { ($0 as? [String: Any]).flatMap(linkPreview) }.first
    }
    
    private static func linkPreview(_ entry: [String: Any]) -> LinkPreview? {
        guard let url = string(entry["matched_url"]) ?? string(entry["og:url"]), url.hasPrefix("http") else { return nil }
        let title = string(entry["og:title"])
        let description = string(entry["og:description"])
        guard title != nil || description != nil else { return nil }
        var image: LinkPreviewImage?
        let width = integer(entry["og:image:width"])
        let height = integer(entry["og:image:height"])
        if let encryption = entry["beeper:image:encryption"] as? [String: Any], let url = string(encryption["url"]) {
            image = LinkPreviewImage(mxcURL: url, encryptedSourceJSON: serialize(["file": encryption]), width: width, height: height)
        } else if let url = string(entry["og:image"]), url.hasPrefix("mxc://") {
            image = LinkPreviewImage(mxcURL: url, encryptedSourceJSON: nil, width: width, height: height)
        }
        return LinkPreview(url: url, title: title, description: description, siteName: string(entry["og:site_name"]), image: image)
    }
    
    private static func encryptedFile(_ mxcURL: String, _ encryption: EncryptedAttachment) -> [String: Any] {
        ["url": mxcURL,
         "key": ["kty": "oct", "key_ops": ["encrypt", "decrypt"], "alg": "A256CTR", "k": encryption.key, "ext": true],
         "iv": encryption.iv,
         "hashes": ["sha256": encryption.sha256],
         "v": "v2"]
    }
    
    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
    
    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: number
        case let number as Double: Int(number)
        case let number as NSNumber: number.intValue
        default: nil
        }
    }
    
    static func serialize(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
