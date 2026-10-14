//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// What someone typed in "Your workspace": a workspace name (`acme`) or, with a dot, a server name (`artise.co`).
public enum WorkspaceAddress: Equatable, Sendable {
    case slug(String)
    case serverName(String)
    
    /// Reads what someone typed; `nil` when it can't be a workspace or a server name.
    /// Spaces and capitals don't matter, and a pasted web address or Matrix ID gives its server name.
    public init?(input: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let colon = text.firstIndex(of: ":"), text.hasPrefix("@") {
            text = String(text[text.index(after: colon)...]) // @ana:acme.artise.co
        }
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        
        if text.contains(".") {
            guard Self.isServerName(text) else { return nil }
            self = .serverName(text)
        } else {
            guard WorkspaceSlug.isValid(text) else { return nil }
            self = .slug(text)
        }
    }
    
    /// What to keep as "the last workspace used" and show in the field next time.
    public var text: String {
        switch self {
        case .slug(let slug): slug
        case .serverName(let serverName): serverName
        }
    }
    
    /// Host names (`acme.artise.co`), with an optional port.
    private static func isServerName(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let host = parts.first, !host.isEmpty, host.count <= 253 else { return false }
        if parts.count == 2 {
            guard let port = Int(parts[1]), (1...65535).contains(port) else { return false }
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}

/// A workspace's short name, as Artise's directory knows it: 3 to 30 of `a-z`, `0-9` and `-`,
/// without a hyphen at either end or two in a row.
public enum WorkspaceSlug {
    public static func isValid(_ slug: String) -> Bool {
        (3...30).contains(slug.count)
            && slug.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
            && !slug.hasPrefix("-") && !slug.hasSuffix("-") && !slug.contains("--")
    }
}
