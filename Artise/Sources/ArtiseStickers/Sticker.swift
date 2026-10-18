//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A sticker in the picker: one of the person's own, or one from the starter pack.
public struct Sticker: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    /// Read aloud by screen readers and shown by apps that can't draw stickers.
    public let description: String
    public let source: StickerSource
    public let width: Int
    public let height: Int
    public let mimeType: String
    public let size: Int
    
    public init(id: String, description: String, source: StickerSource, width: Int, height: Int, mimeType: String, size: Int) {
        self.id = id
        self.description = description
        self.source = source
        self.width = width
        self.height = height
        self.mimeType = mimeType
        self.size = size
    }
    
    func with(id: String) -> Sticker {
        Sticker(id: id, description: description, source: source, width: width, height: height, mimeType: mimeType, size: size)
    }
}

public enum StickerSource: Equatable, Hashable, Sendable {
    /// On the server already: the person's own stickers, and stickers someone sent.
    case uploaded(mxcURL: String)
    /// In the app (the starter pack): uploaded the first time it's sent.
    case starter(fileName: String)
}

/// A picture ready to become a sticker: made from a photo, or pasted from a sticker keyboard.
public struct StickerPicture: Equatable, Sendable {
    public let data: Data
    public let width: Int
    public let height: Int
    public let mimeType: String
    
    public init(data: Data, width: Int, height: Int, mimeType: String) {
        self.data = data
        self.width = width
        self.height = height
        self.mimeType = mimeType
    }
}

public enum StickerError: Error, Equatable {
    /// The starter pack's picture couldn't be read from the app.
    case missingStarterPicture
    /// Only stickers already on the server go in the person's pack.
    case notUploaded
}
