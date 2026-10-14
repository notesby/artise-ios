//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An invite to a workspace: `https://join.artise.co/{slug}/{code}`.
public struct InviteLink: Equatable, Sendable {
    public static let host = "join.artise.co"
    
    public let slug: String
    public let code: String
    /// The link itself. Opened in a browser, the server sends it on to the join page.
    public let url: URL
    
    public init?(url: URL) {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == Self.host else { return nil }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard segments.count == 2 || (segments.count == 3 && segments.last == "") else { return nil }
        let slug = segments[segments.startIndex].lowercased()
        let code = String(segments[segments.startIndex + 1])
        guard WorkspaceSlug.isValid(slug), Self.isValid(code: code) else { return nil }
        self.slug = slug
        self.code = code
        self.url = url
    }
    
    /// The join page for this invite: `{join_url}/{code}`, or the link itself before the directory sends `join_url`.
    public func joinPageURL(for workspace: WorkspaceInfo) -> URL {
        workspace.joinURL?.appendingPathComponent(code) ?? url
    }
    
    /// `[A-Za-z0-9_-]{6,64}`.
    static func isValid(code: String) -> Bool {
        (6...64).contains(code.count) && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}
