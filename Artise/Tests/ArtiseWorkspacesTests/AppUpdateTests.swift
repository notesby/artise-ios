//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseWorkspaces
import Foundation
import Testing

struct AppUpdateTests {
    /// Versions compare as numbers, part by part; a missing part counts as 0.
    @Test
    func blocksOnlyOlderVersions() {
        let minimum = MinimumAppVersion(ios: [26, 9, 10])
        #expect(minimum.blocks(appVersion: "26.9.9"))
        #expect(minimum.blocks(appVersion: "26.9"))
        #expect(minimum.blocks(appVersion: "25.12.30"))
        #expect(!minimum.blocks(appVersion: "26.9.10"))
        #expect(!minimum.blocks(appVersion: "26.10.0"))
        #expect(!minimum.blocks(appVersion: "26.9.10.1"))
        #expect(!minimum.blocks(appVersion: "27"))
    }
    
    /// No minimum, or a version that can't be read, never blocks.
    @Test
    func neverBlocksWithoutAReadableMinimum() {
        #expect(!MinimumAppVersion(ios: nil).blocks(appVersion: "1.0"))
        #expect(!MinimumAppVersion(ios: [26]).blocks(appVersion: "beta"))
        #expect(MinimumAppVersion(value: [String: Any]())?.ios == nil)
        #expect(MinimumAppVersion(value: ["ios": "26.9.10", "android": 202_609_100])?.ios == [26, 9, 10])
        #expect(MinimumAppVersion(value: ["ios": "26.x"])?.ios == nil)
        #expect(MinimumAppVersion(value: ["ios": "-1.2"])?.ios == nil)
        #expect(MinimumAppVersion(value: "26.9.10") == nil)
    }
    
    /// Only an https App Store link is kept.
    @Test
    func storeLinks() {
        #expect(StoreLinks(value: ["ios": "https://apps.apple.com/app/id1"])?.ios?.absoluteString == "https://apps.apple.com/app/id1")
        #expect(StoreLinks(value: ["ios": "itms-apps://x"])?.ios == nil)
        #expect(StoreLinks(value: ["android": "https://play.google.com/x"]) == StoreLinks(ios: nil))
        #expect(StoreLinks(value: nil) == nil)
    }
}
