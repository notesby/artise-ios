//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Which connections notes may update on when nobody is looking at them: while the app is open on another screen,
/// when iOS wakes it, and (once the server sends them) on silent pushes. Opening Notas always updates them, and
/// Low Data Mode always waits for that. The same setting as on Android; on this phone, for every account.
public enum NotesBackgroundSync: String, CaseIterable, Sendable {
    case wifiOnly
    case wifiAndMobile
    
    /// The phone's connection now, as `NWPath` describes it.
    public struct Connection: Equatable, Sendable {
        public var isOnline: Bool
        /// Mobile data or a hotspot.
        public var isExpensive: Bool
        /// Low Data Mode.
        public var isConstrained: Bool
        
        public init(isOnline: Bool, isExpensive: Bool, isConstrained: Bool) {
            self.isOnline = isOnline
            self.isExpensive = isExpensive
            self.isConstrained = isConstrained
        }
    }
    
    /// Many families are on prepaid mobile data, so it starts with Wi-Fi only.
    public static let standard = Self.wifiOnly
    
    public func allows(_ connection: Connection) -> Bool {
        guard connection.isOnline, !connection.isConstrained else { return false }
        return self == .wifiAndMobile || !connection.isExpensive
    }
}

/// Keeps the setting in the app's defaults.
public struct NotesBackgroundSyncStore: Sendable {
    private let suiteName: String?
    
    /// `suiteName`: `nil` for the app's own defaults.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }
    
    public var setting: NotesBackgroundSync {
        get { defaults?.string(forKey: Self.key).flatMap(NotesBackgroundSync.init) ?? .standard }
        nonmutating set { defaults?.set(newValue.rawValue, forKey: Self.key) }
    }
    
    private var defaults: UserDefaults? {
        suiteName.map { UserDefaults(suiteName: $0) } ?? .standard
    }
    
    static let key = "artise.notesBackgroundSync"
}
