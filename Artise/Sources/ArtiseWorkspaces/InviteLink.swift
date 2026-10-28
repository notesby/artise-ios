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

public extension InviteLink {
    /// Where the app joins for someone already signed in to Artise ID, with no page: `{join_url}/{code}/app`.
    /// `nil` before the directory sends `join_url`.
    func appJoinURL(for workspace: WorkspaceInfo) -> URL? {
        workspace.joinURL?.appendingPathComponent(code).appendingPathComponent("app")
    }
}

/// What came of joining a workspace from the app with an Artise ID access token.
public enum InviteAppJoin: Equatable, Sendable {
    /// In: a new account (201), or the Artise ID's account there got the invitation's chats (200, `already`).
    /// Sign-in to the workspace with Artise finds the account.
    case joined
    /// 401 `token`: Artise ID didn't accept the access token.
    case tokenRefused
    /// 403 `email_unverified`: the Artise ID's email isn't verified yet.
    case emailUnverified
    /// 404 `invite`: the link doesn't work any more.
    case inviteExpired
    /// 429 `slow`: too many tries.
    case slow
    /// The workspace's server can't join from the app (no `join_url`, or another 404): the join page instead.
    case notOffered
    /// No answer, or one the app can't read.
    case unreachable
    
    static func result(statusCode: Int, body: Data) -> InviteAppJoin {
        let error = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String
        switch (statusCode, error) {
        case (200, _), (201, _):
            return .joined
        case (401, _):
            return .tokenRefused
        case (403, "email_unverified"):
            return .emailUnverified
        case (404, "invite"):
            return .inviteExpired
        case (404, _), (405, _):
            return .notOffered
        case (429, _):
            return .slow
        default:
            return .unreachable
        }
    }
}
