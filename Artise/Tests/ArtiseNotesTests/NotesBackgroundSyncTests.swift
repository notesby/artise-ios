//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

struct NotesBackgroundSyncTests {
    let wifi = NotesBackgroundSync.Connection(isOnline: true, isExpensive: false, isConstrained: false)
    let mobile = NotesBackgroundSync.Connection(isOnline: true, isExpensive: true, isConstrained: false)
    let lowData = NotesBackgroundSync.Connection(isOnline: true, isExpensive: false, isConstrained: true)
    let offline = NotesBackgroundSync.Connection(isOnline: false, isExpensive: false, isConstrained: false)
    
    /// Wi-Fi only skips mobile data; Wi-Fi and mobile data uses both.
    @Test
    func connections() {
        #expect(NotesBackgroundSync.wifiOnly.allows(wifi))
        #expect(!NotesBackgroundSync.wifiOnly.allows(mobile))
        #expect(NotesBackgroundSync.wifiAndMobile.allows(wifi))
        #expect(NotesBackgroundSync.wifiAndMobile.allows(mobile))
    }
    
    /// Low Data Mode and no connection always wait for Notas to be opened.
    @Test
    func lowDataModeAndOffline() {
        for setting in NotesBackgroundSync.allCases {
            #expect(!setting.allows(lowData))
            #expect(!setting.allows(offline))
        }
    }
    
    /// It starts as Wi-Fi only and keeps what was chosen.
    @Test
    func stored() throws {
        let suite = "notes-background-sync-tests"
        try #require(UserDefaults(suiteName: suite)).removeObject(forKey: NotesBackgroundSyncStore.key)
        let store = NotesBackgroundSyncStore(suiteName: suite)
        #expect(store.setting == .wifiOnly)
        store.setting = .wifiAndMobile
        #expect(NotesBackgroundSyncStore(suiteName: suite).setting == .wifiAndMobile)
    }
}
