//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An OpenID token from the chat server, as `POST /user/{userId}/openid/request_token` returns it.
public struct NotesOpenIDToken: Sendable {
    public let accessToken: String
    public let expiresIn: TimeInterval
    
    public init(accessToken: String, expiresIn: TimeInterval) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
    }
}

/// Where the Notes API client gets its sign-in token. A seam, so tests don't need a Matrix client.
public protocol NotesTokenSource: Sendable {
    /// A valid token, requesting a new one when needed.
    func token() async throws(NotesError) -> String
    /// Forgets `rejected` after the server refused it, so the next `token()` asks for a new one.
    func invalidate(_ rejected: String) async
}

/// Hands out the OpenID token the Notes API signs in with. The Matrix access token never leaves the app.
///
/// A token is reused until a minute before it expires; `invalidate` drops it after a `401`.
public actor OpenIDNotesTokenSource: NotesTokenSource {
    /// Refresh a minute early so a request never goes out with a token about to expire.
    static let refreshMargin: TimeInterval = 60
    
    private let requestToken: @Sendable () async throws -> NotesOpenIDToken
    private let now: @Sendable () -> Date
    private var current: (token: String, expiresAt: Date)?
    private var inFlight: Task<NotesOpenIDToken, Error>?
    
    /// - Parameter requestToken: asks the chat server for a new OpenID token.
    public init(now: @escaping @Sendable () -> Date = Date.init,
                requestToken: @escaping @Sendable () async throws -> NotesOpenIDToken) {
        self.now = now
        self.requestToken = requestToken
    }
    
    public func token() async throws(NotesError) -> String {
        if let current, now() < current.expiresAt.addingTimeInterval(-Self.refreshMargin) {
            return current.token
        }
        // Requests that start together share one call to the server.
        let task = inFlight ?? Task { try await requestToken() }
        inFlight = task
        defer { inFlight = nil }
        do {
            let fresh = try await task.value
            current = (fresh.accessToken, now().addingTimeInterval(fresh.expiresIn))
            return fresh.accessToken
        } catch {
            throw .unauthorized("No OpenID token: \(error.localizedDescription)")
        }
    }
    
    public func invalidate(_ rejected: String) {
        // Another request may already have refreshed it; only drop the token that was refused.
        if current?.token == rejected {
            current = nil
        }
    }
}
