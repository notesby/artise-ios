//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

/// How Artise's chat timeline differs from Element's.
public enum ArtiseTimeline {
    /// How long to hold a message before its actions and reactions open: 150 ms (Element waits about 750 ms;
    /// the Android app 250 ms). Holding a link in a message opens the message's actions too.
    public static let messageHoldMilliseconds = 150
    
    /// The touch-and-hold gesture itself needs this long before it starts.
    public static let gestureMinimumMilliseconds = 150
    
    /// The gesture's minimum, in seconds, for `UILongPressGestureRecognizer`.
    public static var gestureMinimumSeconds: Double {
        Double(gestureMinimumMilliseconds) / 1000
    }
    
    /// What's left to wait after the gesture starts.
    public static var extraWaitMilliseconds: Int {
        max(messageHoldMilliseconds - gestureMinimumMilliseconds, 0)
    }
}
