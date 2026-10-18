//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Finds the web link to preview in what someone typed, as the Android app does.
public enum LinkFinder {
    // Links into chats (matrix.to) open in the app: nothing to preview.
    private static let skippedHosts: Set = ["matrix.to"]
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?'*_~")
    
    /// The first web link in `text` (`https://…`, `http://…` or `www.…`), as a full URL, or `nil`.
    public static func firstLink(_ text: String) -> String? {
        let pattern = /(?i)\b(?:https?:\/\/|www\.)[^\s<>"]+/
        for match in text.matches(of: pattern) {
            var url = trimEnd(String(match.output))
            if url.lowercased().hasPrefix("www.") {
                url = "https://" + url
            }
            if let host = host(of: url), !host.isEmpty, host.contains("."), !skippedHosts.contains(host) {
                return url
            }
        }
        return nil
    }
    
    /// "https://www.example.com/a" → "www.example.com".
    public static func host(of url: String) -> String? {
        guard let schemeEnd = url.range(of: "://") else { return nil }
        var host = Substring(url[schemeEnd.upperBound...])
        for separator in ["/", "?", "#"] {
            host = host.prefix { String($0) != separator }
        }
        if let at = host.lastIndex(of: "@") {
            host = host[host.index(after: at)...]
        }
        host = host.prefix { $0 != ":" }
        return host.isEmpty ? nil : host.lowercased()
    }
    
    /// "https://a.com/x)." → "https://a.com/x": punctuation after a link, and a ")" it doesn't open.
    private static func trimEnd(_ candidate: String) -> String {
        var url = trimmingTrailing(candidate)
        while url.hasSuffix(")"), count("(", in: url) < count(")", in: url) {
            url = trimmingTrailing(String(url.dropLast()))
        }
        return url
    }
    
    private static func count(_ character: Character, in text: String) -> Int {
        text.reduce(0) { $1 == character ? $0 + 1 : $0 }
    }
    
    private static func trimmingTrailing(_ text: String) -> String {
        var scalars = Substring(text)
        while let last = scalars.unicodeScalars.last, trailingPunctuation.contains(last) {
            scalars = scalars.dropLast()
        }
        return String(scalars)
    }
}
