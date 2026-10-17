//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The oldest app a workspace (or Artise ID) still works with: `min_app_version`, `{"android": 202609100, "ios": "26.9.10"}`.
/// Only the iOS entry matters here; empty means no minimum.
public struct MinimumAppVersion: Codable, Equatable, Sendable {
    /// Dot-separated numbers, e.g. `[26, 9, 10]`.
    public let ios: [Int]?
    
    public init(ios: [Int]?) {
        self.ios = ios
    }
    
    /// `nil` when the value isn't an object; an object without a readable `ios` entry is "no minimum".
    init?(value: Any?) {
        guard let object = value as? [String: Any] else { return nil }
        self.init(ios: (object["ios"] as? String).flatMap(Self.numbers))
    }
    
    /// Whether this app version is older than the minimum. A version that can't be read is never blocked.
    public func blocks(appVersion: String) -> Bool {
        guard let minimum = ios, let installed = Self.numbers(appVersion) else { return false }
        for index in 0..<max(minimum.count, installed.count) {
            let have = index < installed.count ? installed[index] : 0
            let need = index < minimum.count ? minimum[index] : 0
            if have != need {
                return have < need
            }
        }
        return false
    }
    
    /// "26.9.10" → [26, 9, 10]; `nil` for anything else.
    static func numbers(_ text: String) -> [Int]? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        let numbers = parts.compactMap { part in part.allSatisfy(\.isASCII) ? Int(part) : nil }
        return numbers.count == parts.count && numbers.allSatisfy { $0 >= 0 } ? numbers : nil
    }
}

/// Where to update the app (`store_links`): only an https link for iOS is kept, `nil` until the App Store URL exists.
public struct StoreLinks: Codable, Equatable, Sendable {
    public let ios: URL?
    
    public init(ios: URL?) {
        self.ios = ios
    }
    
    init?(value: Any?) {
        guard let object = value as? [String: Any] else { return nil }
        self.init(ios: (object["ios"] as? String).flatMap(WorkspaceURL.https))
    }
}
