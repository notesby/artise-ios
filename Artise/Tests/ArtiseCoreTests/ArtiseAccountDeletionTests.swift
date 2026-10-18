//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseCore
import Foundation
import Testing

// The same cases as the Android app's DefaultAccountDeletionTest.

struct ArtiseAccountDeletionTests {
    let defaults = UserDefaults(suiteName: "artise-tests-\(UUID().uuidString)") ?? .standard
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let page = URL(staticString: "https://chat.artise.co/account/delete")
    
    /// The page is in Spanish when the app is, and in English otherwise.
    @Test
    func pageFollowsTheLanguage() {
        #expect(ArtiseAccountDeletion.pageURL(page, language: "es-MX").absoluteString == "https://chat.artise.co/account/delete?lang=es")
        #expect(ArtiseAccountDeletion.pageURL(page, language: "en").absoluteString == "https://chat.artise.co/account/delete")
        #expect(ArtiseAccountDeletion.pageURL(page, language: nil) == page)
    }
    
    /// A sign-out soon after opening the page counts as the deletion, once.
    @Test
    func startedIsUsedOnce() {
        let deletion = ArtiseAccountDeletion(defaults: defaults)
        deletion.markStarted(now: start)
        
        #expect(deletion.consumeStarted(now: start.addingTimeInterval(120)))
        #expect(!deletion.consumeStarted(now: start.addingTimeInterval(130)))
    }
    
    /// After an hour, a sign-out has another cause.
    @Test
    func startedExpires() {
        let deletion = ArtiseAccountDeletion(defaults: defaults)
        deletion.markStarted(now: start)
        
        #expect(!deletion.consumeStarted(now: start.addingTimeInterval(3601)))
    }
    
    /// Without the page having been opened, nothing counts as a deletion.
    @Test
    func nothingStarted() {
        #expect(!ArtiseAccountDeletion(defaults: defaults).consumeStarted(now: start))
    }
}
