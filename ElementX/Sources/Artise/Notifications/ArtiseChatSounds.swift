//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// A chat's own notification sound, on this phone only: one of Element's or the phone's sounds, or an audio file the
/// person picked ("Your sounds", Element's tone library). The chosen sound is copied to a file of its own in
/// Library/Sounds, where the notification extension finds it by name.
nonisolated enum ArtiseChatSounds {
    static let store = ChatSoundStore(suiteName: AppSettings.suiteName)
    /// Only its library is used (picked files, conversion); the app-wide tone stays Element's setting.
    static let toneManager = NotificationToneManager(appSettings: .volatile())
    /// The longest sound iOS plays for a notification; longer files are cut.
    static let maxSeconds = NotificationToneManager.artiseMaxSeconds
    /// Bigger files are refused.
    static let maxBytes = 10 * 1024 * 1024
    
    private static var soundsDirectory: URL {
        NotificationToneManager.libraryLocation.deletingLastPathComponent()
    }
    
    static func choose(_ tone: NotificationTone, userID: String, roomID: String) throws {
        let name = ChatSoundStore.fileName(userID: userID, roomID: roomID)
        let destination = soundsDirectory.appending(component: name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: NotificationToneManager.toneLocation(for: tone), to: destination)
        store.setSound(.file(name: name, label: tone.label), userID: userID, roomID: roomID)
    }
    
    static func silence(userID: String, roomID: String) {
        removeFile(userID: userID, roomID: roomID)
        store.setSound(.silent, userID: userID, roomID: roomID)
    }
    
    /// Back to the app's sound (Settings → Notifications).
    static func reset(userID: String, roomID: String) {
        removeFile(userID: userID, roomID: roomID)
        store.setSound(nil, userID: userID, roomID: roomID)
    }
    
    /// Signing out: the account's chat sounds go; "Your sounds" stay for the next account.
    static func removeAll(userID: String) {
        for roomID in store.roomIDs(userID: userID) {
            reset(userID: userID, roomID: roomID)
        }
    }
    
    /// Removes a picked file from "Your sounds"; the account's chats that used it go back to Default, as on Android.
    static func removeFromYourSounds(_ tone: NotificationTone, userID: String) throws {
        try toneManager.deleteCustomTone(tone)
        for roomID in store.roomIDs(userID: userID, usingSoundNamed: tone.label) {
            reset(userID: userID, roomID: roomID)
        }
    }
    
    /// A picked file's length, to warn before it's cut; `nil` when it can't be read.
    static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
    
    private static func removeFile(userID: String, roomID: String) {
        try? FileManager.default.removeItem(at: soundsDirectory.appending(component: ChatSoundStore.fileName(userID: userID, roomID: roomID)))
    }
}
