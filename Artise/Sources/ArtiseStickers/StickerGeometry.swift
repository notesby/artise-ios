//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A box of pixels in a picture: `left` and `top` are in, `right` and `bottom` are just past it.
public struct PixelBox: Equatable, Sendable {
    public let left: Int
    public let top: Int
    public let right: Int
    public let bottom: Int
    
    public var width: Int {
        right - left
    }
    
    public var height: Int {
        bottom - top
    }
    
    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}

/// How a photo becomes a sticker: trimmed to what's visible and sized for sending, as on Android.
public enum StickerGeometry {
    /// Stickers are at most this wide and tall: sharp on any phone, small to send.
    public static let maxSide = 512
    
    /// Pixels less opaque than this are background left around a cut-out.
    static let visibleAlpha: UInt8 = 16
    
    /// The smallest box around the visible pixels (`alphaAt` gives a pixel's opacity, 0-255), with `padding` pixels
    /// of air around it; `nil` when nothing is visible (the cut-out found nothing).
    public static func visibleBox(width: Int, height: Int, padding: Int, alphaAt: (_ x: Int, _ y: Int) -> UInt8) -> PixelBox? {
        var left = width
        var top = height
        var right = -1
        var bottom = -1
        for y in 0..<height {
            for x in 0..<width where alphaAt(x, y) >= visibleAlpha {
                left = min(left, x)
                top = min(top, y)
                right = max(right, x)
                bottom = max(bottom, y)
            }
        }
        guard right >= 0 else { return nil }
        return PixelBox(left: max(0, left - padding),
                        top: max(0, top - padding),
                        right: min(width, right + 1 + padding),
                        bottom: min(height, bottom + 1 + padding))
    }
    
    /// The air left around a cut-out: a fortieth of the picture's longer side.
    public static func padding(width: Int, height: Int) -> Int {
        max(width, height) / 40
    }
    
    /// The centered square of a picture, for a photo used whole.
    public static func centerSquare(width: Int, height: Int) -> PixelBox {
        let side = min(width, height)
        let left = (width - side) / 2
        let top = (height - side) / 2
        return PixelBox(left: left, top: top, right: left + side, bottom: top + side)
    }
    
    /// `width` × `height` scaled down to fit within `maxSide`, keeping its shape; never scaled up.
    public static func fit(width: Int, height: Int) -> (width: Int, height: Int) {
        let scale = min(1, Double(maxSide) / Double(max(width, height)))
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }
}
