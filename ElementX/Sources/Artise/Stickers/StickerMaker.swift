//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseStickers
import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Vision

/// A sticker just made from a photo, shown before it's saved.
nonisolated struct MadeSticker: Identifiable, Sendable {
    let id = UUID()
    let picture: StickerPicture
    /// `false` when nothing could be cut out and the whole photo is used.
    let isCutOut: Bool
}

nonisolated enum StickerMakerError: Error {
    case unreadable
}

/// Makes stickers from photos on the phone, as the Android app does: the subject is cut out (Vision), trimmed with
/// a little air, sized to 512 px at most and saved with its transparent background. Pictures that are already cut
/// out (from sticker apps) are kept as they are.
nonisolated enum StickerMaker {
    /// Big enough for a clean cut-out, small enough to be quick.
    private static let decodeSide = 1280
    private static let webPQuality = 0.85
    
    static func make(from data: Data) async throws -> MadeSticker {
        try await Task.detached(priority: .userInitiated) {
            try makeNow(from: data)
        }.value
    }
    
    /// A picture pasted from a sticker keyboard: a small PNG, WebP or GIF; PNG and WebP pictures also need a
    /// transparent background, so a small screenshot still goes as a picture. `nil` when it isn't a sticker.
    static func keyboardSticker(from providers: [NSItemProvider]) async -> StickerPicture? {
        guard providers.count == 1, let provider = providers.first else { return nil }
        for type in [UTType.png, .webP, .gif] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            guard let mimeType = type.preferredMIMEType,
                  KeyboardStickers.isStickerType(mimeType),
                  let data = await loadData(provider, type: type),
                  KeyboardStickers.isStickerSize(data.count),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let size = pixelSize(source) else {
                return nil
            }
            if type != .gif {
                guard let thumbnail = downsample(source, side: 256), isAlreadyCutOut(thumbnail) else { return nil }
            }
            return StickerPicture(data: data, width: size.width, height: size.height, mimeType: mimeType)
        }
        return nil
    }
    
    /// The provider's data for `type`; `NSItemProvider` has no async variant of this call.
    private static func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
    
    // MARK: - Making
    
    private static func makeNow(from data: Data) throws -> MadeSticker {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = downsample(source, side: decodeSide) else {
            throw StickerMakerError.unreadable
        }
        let cutOut = isAlreadyCutOut(decoded) ? decoded : cutOutSubject(decoded)
        let box = cutOut.flatMap(visibleBox)
        let picture = box != nil ? cutOut ?? decoded : decoded
        let area = box ?? StickerGeometry.centerSquare(width: decoded.width, height: decoded.height)
        let size = StickerGeometry.fit(width: area.width, height: area.height)
        guard let cropped = picture.cropping(to: CGRect(x: area.left, y: area.top, width: area.width, height: area.height)),
              let scaled = draw(cropped, width: size.width, height: size.height),
              let encoded = encode(scaled) else {
            throw StickerMakerError.unreadable
        }
        return MadeSticker(picture: StickerPicture(data: encoded.data, width: size.width, height: size.height, mimeType: encoded.mimeType),
                           isCutOut: box != nil)
    }
    
    /// The photo's subjects (people, pets, things) on a transparent background, or `nil` when Vision finds none.
    private static func cutOutSubject(_ image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let masked = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
            let ciImage = CIImage(cvPixelBuffer: masked)
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        } catch {
            MXLog.error("Stickers: the cut-out failed: \(error)")
            return nil
        }
    }
    
    /// A picture with transparent edges already, like stickers from other apps.
    private static func isAlreadyCutOut(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            guard let box = visibleBox(image) else { return false }
            return box != PixelBox(left: 0, top: 0, right: image.width, bottom: image.height)
        }
    }
    
    private static func visibleBox(_ image: CGImage) -> PixelBox? {
        guard let pixels = rgbaPixels(image) else { return nil }
        let width = image.width
        return StickerGeometry.visibleBox(width: width, height: image.height,
                                          padding: StickerGeometry.padding(width: width, height: image.height)) { x, y in
            pixels[(y * width + x) * 4 + 3]
        }
    }
    
    // MARK: - Pixels
    
    /// Upright (the camera's orientation applied) and no bigger than `side`.
    private static func downsample(_ source: CGImageSource, side: Int) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceThumbnailMaxPixelSize: side]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
    
    private static func pixelSize(_ source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (max(1, width), max(1, height))
    }
    
    private static func rgbaPixels(_ image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = rgbaContext(buffer.baseAddress, width: image.width, height: image.height) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? pixels : nil
    }
    
    private static func draw(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = rgbaContext(nil, width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
    
    private static func rgbaContext(_ data: UnsafeMutableRawPointer?, width: Int, height: Int) -> CGContext? {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    
    /// WebP like the Android app when this iOS can write it, PNG otherwise; both keep the transparent background.
    private static func encode(_ image: CGImage) -> (data: Data, mimeType: String)? {
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        let type: UTType = writable.contains(UTType.webP.identifier) ? .webP : .png
        let data = NSMutableData()
        guard let mimeType = type.preferredMIMEType,
              let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: webPQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (data as Data, mimeType)
    }
}
