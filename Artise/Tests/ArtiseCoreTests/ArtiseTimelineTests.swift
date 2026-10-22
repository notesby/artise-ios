//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseCore
import Testing

struct ArtiseTimelineTests {
    /// Holding a message opens its reactions after 150 ms: no wait after the gesture starts.
    @Test
    func holdIs150Milliseconds() {
        #expect(ArtiseTimeline.messageHoldMilliseconds == 150)
        #expect(ArtiseTimeline.extraWaitMilliseconds == 0)
        #expect(ArtiseTimeline.gestureMinimumSeconds == 0.15)
    }
}
