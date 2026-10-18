//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The 48 stickers that come with the app: Microsoft's Fluent Emoji 3D (MIT License), the same as on Android.
public struct StarterPack: Sendable {
    /// The pack in the app.
    public static let bundled = StarterPack(folder: Bundle.module.url(forResource: "Starter", withExtension: nil))
    
    private let folder: URL?
    
    public init(folder: URL?) {
        self.folder = folder
    }
    
    /// The stickers, named in Spanish when `language` is Spanish and in English otherwise.
    public func stickers(language: String) -> [Sticker] {
        guard let folder, let manifest = try? Data(contentsOf: folder.appending(path: "pack.json")) else { return [] }
        return Self.stickers(manifest: manifest, language: language)
    }
    
    /// Where a starter sticker's picture is, to show it in the picker.
    public func url(for fileName: String) -> URL? {
        folder?.appending(path: fileName)
    }
    
    /// A starter sticker's picture, to upload it.
    public func data(for fileName: String) throws(StickerError) -> Data {
        guard let url = url(for: fileName), let data = try? Data(contentsOf: url) else { throw .missingStarterPicture }
        return data
    }
    
    static func stickers(manifest: Data, language: String) -> [Sticker] {
        guard let pack = try? JSONDecoder().decode(Manifest.self, from: manifest) else { return [] }
        return pack.stickers.map { entry in
            Sticker(id: "starter:" + entry.id,
                    description: language == "es" ? entry.es : entry.en,
                    source: .starter(fileName: entry.id + ".webp"),
                    width: entry.w,
                    height: entry.h,
                    mimeType: "image/webp",
                    size: entry.size)
        }
    }
    
    private struct Manifest: Decodable {
        let stickers: [Entry]
    }
    
    private struct Entry: Decodable {
        let id: String
        let en: String
        let es: String
        let w: Int
        let h: Int
        let size: Int
    }
}
