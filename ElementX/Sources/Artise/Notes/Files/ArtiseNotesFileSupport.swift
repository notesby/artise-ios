//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Foundation
import ImageIO
import Network
import UniformTypeIdentifiers

/// Turns phone photos into JPEGs every app can show, before they're added to notes, as the Android app does.
///
/// iPhones save HEIC photos, which web browsers and Obsidian on computers often can't show, and which are large.
/// Big JPEG, PNG and WebP photos are made smaller too; small common ones stay exactly as they were.
nonisolated enum NotesPhotoConverter {
    /// The long side of a converted photo: sharp on any phone or laptop screen.
    static let maxSide = 2560
    static let jpegQuality = 0.85
    /// Photos in these formats are always converted: few apps can show them.
    static let always: Set = ["image/heic", "image/heif", "image/heic-sequence", "image/heif-sequence", "image/avif"]
    /// Photos in these formats are converted only when big.
    static let whenBig: Set = ["image/jpeg", "image/png", "image/webp"]
    static let bigBytes = 3 * 1024 * 1024
    
    /// A JPEG version of the photo, or `nil` to keep the file as it is (not a photo, a GIF, or already small).
    static func toJPEG(_ data: Data, contentType: String) -> Data? {
        let type = contentType.lowercased()
        let isAlways = always.contains(type)
        guard isAlways || whenBig.contains(type),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let isTooLarge = max(width, height) > maxSide
        if !isAlways, !isTooLarge, data.count <= bigBytes {
            return nil
        }
        // The thumbnail API reads the photo turned upright and scaled, in one step.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxSide)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// Whether photos may download ahead of time: only on Wi-Fi or another connection that isn't expensive, and not
/// in Low Data Mode. Many families are on prepaid mobile data, so the app never spends it on photos nobody asked to see.
/// Notes nobody is looking at update on the connections the person chose (`NotesBackgroundSync`).
final nonisolated class NotesPrefetchPolicy: Sendable {
    static let shared = NotesPrefetchPolicy()
    
    private let monitor = NWPathMonitor()
    
    private init() {
        monitor.start(queue: DispatchQueue(label: "co.artise.notes.network"))
    }
    
    var canPrefetch: Bool {
        NotesBackgroundSync.wifiOnly.allows(connection)
    }
    
    var canSyncInBackground: Bool {
        NotesBackgroundSyncStore().setting.allows(connection)
    }
    
    private var connection: NotesBackgroundSync.Connection {
        let path = monitor.currentPath
        return .init(isOnline: path.status == .satisfied, isExpensive: path.isExpensive, isConstrained: path.isConstrained)
    }
}
