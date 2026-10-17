//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Where the Artise ID tokens live on the phone (the Keychain, in the app).
public protocol ArtiseIDTokenStorage: Sendable {
    func load() -> ArtiseIDTokens?
    func save(_ tokens: ArtiseIDTokens)
    func remove()
}

/// Keeps the Artise ID tokens usable. Artise ID rotates refresh tokens: each refresh returns a new one and refuses
/// the old one from then on, so only one refresh runs at a time and the new tokens are stored before they're used.
public actor ArtiseIDTokenKeeper {
    private let client: ArtiseIDClient
    private let storage: ArtiseIDTokenStorage
    private let now: @Sendable () -> Date
    private var refreshing: Task<Result<ArtiseIDTokens, ArtiseIDError>, Never>?
    /// Bumped by `forget()`, so a refresh still running then doesn't store tokens again.
    private var generation = 0
    
    public init(client: ArtiseIDClient, storage: ArtiseIDTokenStorage, now: @escaping @Sendable () -> Date = { .now }) {
        self.client = client
        self.storage = storage
        self.now = now
    }
    
    public var hasTokens: Bool {
        storage.load() != nil
    }
    
    /// Right after signing in.
    public func keep(_ tokens: ArtiseIDTokens) {
        storage.save(tokens)
    }
    
    /// A usable access token, refreshed when needed. `nil` when the person has to sign in to Artise ID again
    /// (no tokens, or Artise ID refused them); `.unreachable` when offline, keeping the tokens for later.
    public func accessToken() async -> Result<String, ArtiseIDError>? {
        guard let tokens = storage.load() else { return nil }
        if tokens.isFresh(at: now()) {
            return .success(tokens.accessToken)
        }
        switch await refreshed(tokens) {
        case .success(let renewed):
            return .success(renewed.accessToken)
        case .failure(.unreachable):
            return .failure(.unreachable)
        case .failure:
            // Only these tokens: a new sign-in meanwhile keeps its own.
            if storage.load()?.refreshToken == tokens.refreshToken {
                storage.remove()
            }
            return nil
        }
    }
    
    /// Called after a 401 with a token that looked fresh: drop it so the next call refreshes.
    public func accessTokenRejected(_ accessToken: String) {
        guard let tokens = storage.load(), tokens.accessToken == accessToken else { return }
        storage.save(ArtiseIDTokens(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, expiresAt: .distantPast))
    }
    
    /// Signing out of the last workspace: the tokens leave the phone, and the refresh token is given back.
    public func forget() async {
        let refreshToken = storage.load()?.refreshToken
        storage.remove()
        refreshing = nil
        generation += 1
        guard let refreshToken, let configuration = await client.configuration(),
              let endpoints = await client.endpoints(for: configuration) else {
            return
        }
        await client.revoke(refreshToken: refreshToken, configuration: configuration, endpoints: endpoints)
    }
    
    // MARK: - Private
    
    private func refreshed(_ tokens: ArtiseIDTokens) async -> Result<ArtiseIDTokens, ArtiseIDError> {
        if let refreshing {
            return await refreshing.value
        }
        let generation = generation
        let task = Task { await self.refresh(tokens, generation: generation) }
        refreshing = task
        let result = await task.value
        refreshing = nil
        return result
    }
    
    private func refresh(_ tokens: ArtiseIDTokens, generation: Int) async -> Result<ArtiseIDTokens, ArtiseIDError> {
        guard tokens.refreshToken != nil else { return .failure(.unauthorized) }
        guard let configuration = await client.configuration(), let endpoints = await client.endpoints(for: configuration) else {
            return .failure(.unreachable)
        }
        let result = await client.refresh(tokens, configuration: configuration, endpoints: endpoints)
        guard generation == self.generation else { return .failure(.unauthorized) }
        if case .success(let renewed) = result {
            storage.save(renewed)
        }
        return result
    }
}
