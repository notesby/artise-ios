//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A chat's own notification sound, on this phone only (decided 17 Oct: nothing is synced to other phones).
public enum ChatSound: Codable, Equatable, Sendable {
    /// A sound file in the app's Library/Sounds, with the name the person sees.
    case file(name: String, label: String)
    /// Notifications from this chat show without sound.
    case silent
}

/// Each chat's sound, per account, in the defaults the app shares with the notification extension.
public struct ChatSoundStore: Sendable {
    private let suiteName: String?
    
    /// `suiteName`: the app group; `nil` for the app's own defaults (tests).
    public init(suiteName: String?) {
        self.suiteName = suiteName
    }
    
    public func sound(userID: String, roomID: String) -> ChatSound? {
        guard let data = defaults?.data(forKey: Self.key(userID, roomID)) else { return nil }
        return try? JSONDecoder().decode(ChatSound.self, from: data)
    }
    
    /// `nil` goes back to the app's sound.
    public func setSound(_ sound: ChatSound?, userID: String, roomID: String) {
        guard let sound else {
            defaults?.removeObject(forKey: Self.key(userID, roomID))
            return
        }
        defaults?.set(try? JSONEncoder().encode(sound), forKey: Self.key(userID, roomID))
    }
    
    /// Every chat of this account with its own sound, for clean-up at sign-out.
    public func roomIDs(userID: String) -> [String] {
        let prefix = Self.key(userID, "")
        return (defaults?.dictionaryRepresentation().keys ?? [:].keys).filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
    
    /// The file a chat's sound is copied to: one per chat, so changing it never touches another chat's.
    public static func fileName(userID: String, roomID: String) -> String {
        "artise-chat-\(stableHash(userID + "|" + roomID)).caf"
    }
    
    private var defaults: UserDefaults? {
        suiteName.map { UserDefaults(suiteName: $0) } ?? .standard
    }
    
    static func key(_ userID: String, _ roomID: String) -> String {
        "artise.chatSound.\(userID)|\(roomID)"
    }
    
    /// FNV-1a, so the name stays the same across launches.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
