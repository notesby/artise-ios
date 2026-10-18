//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseCore
import Foundation
import Testing

struct ChatSoundTests {
    /// Each chat keeps its own sound per account; going back to the default removes it.
    @Test
    func perChatAndAccount() {
        let store = ChatSoundStore(suiteName: "chat-sound-tests")
        for room in store.roomIDs(userID: "@a:x") {
            store.setSound(nil, userID: "@a:x", roomID: room)
        }
        #expect(store.sound(userID: "@a:x", roomID: "!1:x") == nil)
        store.setSound(.file(name: "artise-chat-1.caf", label: "Risa"), userID: "@a:x", roomID: "!1:x")
        store.setSound(.silent, userID: "@a:x", roomID: "!2:x")
        #expect(store.sound(userID: "@a:x", roomID: "!1:x") == .file(name: "artise-chat-1.caf", label: "Risa"))
        #expect(store.sound(userID: "@a:x", roomID: "!2:x") == .silent)
        #expect(store.sound(userID: "@b:x", roomID: "!1:x") == nil)
        #expect(Set(store.roomIDs(userID: "@a:x")) == ["!1:x", "!2:x"])
        store.setSound(nil, userID: "@a:x", roomID: "!1:x")
        #expect(store.sound(userID: "@a:x", roomID: "!1:x") == nil)
    }
    
    /// Removing a sound from "Your sounds" finds only the chats that use it, in this account.
    @Test
    func chatsUsingASound() {
        let store = ChatSoundStore(suiteName: "chat-sound-tests-using")
        for user in ["@a:x", "@b:x"] {
            for room in store.roomIDs(userID: user) {
                store.setSound(nil, userID: user, roomID: room)
            }
        }
        store.setSound(.file(name: "artise-chat-1.caf", label: "Risa"), userID: "@a:x", roomID: "!1:x")
        store.setSound(.file(name: "artise-chat-2.caf", label: "Campana"), userID: "@a:x", roomID: "!2:x")
        store.setSound(.silent, userID: "@a:x", roomID: "!3:x")
        store.setSound(.file(name: "artise-chat-4.caf", label: "Risa"), userID: "@b:x", roomID: "!1:x")
        #expect(store.roomIDs(userID: "@a:x", usingSoundNamed: "Risa") == ["!1:x"])
        #expect(store.roomIDs(userID: "@a:x", usingSoundNamed: "Otro").isEmpty)
    }
    
    /// A chat's file name is the same every time and differs between chats and accounts.
    @Test
    func fileNames() {
        let name = ChatSoundStore.fileName(userID: "@a:x", roomID: "!1:x")
        #expect(name == ChatSoundStore.fileName(userID: "@a:x", roomID: "!1:x"))
        #expect(name != ChatSoundStore.fileName(userID: "@a:x", roomID: "!2:x"))
        #expect(name != ChatSoundStore.fileName(userID: "@b:x", roomID: "!1:x"))
        #expect(name.hasPrefix("artise-chat-") && name.hasSuffix(".caf"))
    }
}
