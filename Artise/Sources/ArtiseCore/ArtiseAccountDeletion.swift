//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Deleting the account happens on Artise's web page (the App Store requires a way from inside the app). The page
/// does everything and ends the app's session on the server; the app only opens it, and afterwards goes straight back
/// to sign-in instead of explaining why it was signed out. The same as the Android app.
public struct ArtiseAccountDeletion {
    /// Long enough to read the page and confirm; a later sign-out has another cause.
    public static let startedValidity: TimeInterval = 60 * 60
    
    private static let startedKey = "co.artise.accountDeletion.startedAt"
    
    private let defaults: UserDefaults
    
    /// The time the page was opened is kept in the app's defaults, so it survives the app closing while the browser is open.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    /// The page on the account's workspace, in Spanish when the app is.
    public static func pageURL(serverName: String, language: String?) -> URL {
        let pageURL = ArtiseConfiguration.chatURL(serverName: serverName).appending(path: "account/delete")
        guard language?.hasPrefix("es") == true else { return pageURL }
        return pageURL.appending(queryItems: [URLQueryItem(name: "lang", value: "es")])
    }
    
    /// The page was opened: a sign-out that follows soon is the deletion.
    public func markStarted(now: Date = .now) {
        defaults.set(now.timeIntervalSince1970, forKey: Self.startedKey)
    }
    
    /// Whether the session just ended because the account was deleted; true once, then forgotten.
    public func consumeStarted(now: Date = .now) -> Bool {
        guard defaults.object(forKey: Self.startedKey) != nil else { return false }
        let startedAt = defaults.double(forKey: Self.startedKey)
        defaults.removeObject(forKey: Self.startedKey)
        let elapsed = now.timeIntervalSince1970 - startedAt
        return elapsed >= 0 && elapsed <= Self.startedValidity
    }
}
