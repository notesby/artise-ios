//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseCore
import Testing

struct ArtiseTimelineTests {
    /// Holding a message opens its reactions after 250 ms, like on Android: no wait after the gesture starts.
    @Test
    func holdIs250Milliseconds() {
        #expect(ArtiseTimeline.messageHoldMilliseconds == 250)
        #expect(ArtiseTimeline.extraWaitMilliseconds == 0)
    }
}
