//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseWorkspaces
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

struct ArtiseIDTokenKeeperTests {
    static let token = "https://id.artise.co/oauth/v2/token"
    static let revoke = "https://id.artise.co/oauth/v2/revoke"
    static let answers: [String: FakeTransport.Answer] = [
        "https://api.artise.co/v1/sign-in": .init(body: ArtiseIDTests.signIn),
        "https://id.artise.co/.well-known/openid-configuration": .init(body: ArtiseIDTests.discovery)
    ]
    
    /// A fresh access token is used as it is, without asking Artise ID.
    @Test
    func freshTokenIsUsed() async {
        let clock = Clock()
        let storage = MemoryStorage(ArtiseIDTokens(accessToken: "at-1", refreshToken: "rt-1", expiresAt: clock.now.addingTimeInterval(3600)))
        let transport = FakeTransport(Self.answers)
        let keeper = ArtiseIDTokenKeeper(client: ArtiseIDClient(transport: transport, now: { clock.now }), storage: storage, now: { clock.now })
        #expect(await keeper.accessToken() == .success("at-1"))
        #expect(transport.requested.isEmpty)
    }
    
    /// An old access token is refreshed; the new refresh token is stored before it's used, and the old one is gone.
    @Test
    func refreshRotatesAndStores() async {
        let clock = Clock()
        let storage = MemoryStorage(ArtiseIDTokens(accessToken: "at-1", refreshToken: "rt-1", expiresAt: clock.now))
        var answers = Self.answers
        answers[Self.token] = .init(body: #"{"access_token":"at-2","token_type":"Bearer","expires_in":43200,"refresh_token":"rt-2"}"#)
        let transport = FakeTransport(answers)
        let keeper = ArtiseIDTokenKeeper(client: ArtiseIDClient(transport: transport, now: { clock.now }), storage: storage, now: { clock.now })
        #expect(await keeper.accessToken() == .success("at-2"))
        #expect(storage.tokens?.refreshToken == "rt-2")
        let form = String(decoding: transport.requests.last?.httpBody ?? Data(), as: UTF8.self)
        #expect(form == "client_id=395423549856219219&grant_type=refresh_token&refresh_token=rt-1")
    }
    
    /// Two calls at once refresh once: a second refresh with the same (now refused) token would sign the person out.
    @Test
    func oneRefreshAtATime() async {
        let clock = Clock()
        let storage = MemoryStorage(ArtiseIDTokens(accessToken: "at-1", refreshToken: "rt-1", expiresAt: clock.now))
        var answers = Self.answers
        answers[Self.token] = .init(body: #"{"access_token":"at-2","expires_in":43200,"refresh_token":"rt-2"}"#)
        let transport = FakeTransport(answers)
        let keeper = ArtiseIDTokenKeeper(client: ArtiseIDClient(transport: transport, now: { clock.now }), storage: storage, now: { clock.now })
        async let first = keeper.accessToken()
        async let second = keeper.accessToken()
        let results = await [first, second]
        #expect(results == [.success("at-2"), .success("at-2")])
        #expect(transport.requested.filter { $0 == Self.token }.count == 1)
    }
    
    /// Refused tokens leave the phone (sign in again); offline keeps them for later.
    @Test
    func refusedOrOffline() async {
        let clock = Clock()
        let old = ArtiseIDTokens(accessToken: "at-1", refreshToken: "rt-1", expiresAt: clock.now)
        var refusedAnswers = Self.answers
        refusedAnswers[Self.token] = .init(status: 400, body: #"{"error":"invalid_grant"}"#)
        let refusedStorage = MemoryStorage(old)
        let refused = ArtiseIDTokenKeeper(client: ArtiseIDClient(transport: FakeTransport(refusedAnswers), now: { clock.now }),
                                          storage: refusedStorage, now: { clock.now })
        #expect(await refused.accessToken() == nil)
        #expect(refusedStorage.tokens == nil)
        
        let offlineStorage = MemoryStorage(old)
        let offline = ArtiseIDTokenKeeper(client: ArtiseIDClient(transport: FakeTransport([:]), now: { clock.now }),
                                          storage: offlineStorage, now: { clock.now })
        #expect(await offline.accessToken() == .failure(.unreachable))
        #expect(offlineStorage.tokens == old)
        
        let noRefreshToken = MemoryStorage(ArtiseIDTokens(accessToken: "at-1", refreshToken: nil, expiresAt: clock.now))
        let withoutRefresh = ArtiseIDTokenKeeper(client: ArtiseIDClient(transport: FakeTransport(Self.answers), now: { clock.now }),
                                                 storage: noRefreshToken, now: { clock.now })
        #expect(await withoutRefresh.accessToken() == nil)
        #expect(await ArtiseIDTokenKeeper(client: ArtiseIDClient(transport: FakeTransport([:])), storage: MemoryStorage(nil)).accessToken() == nil)
    }
    
    /// A token the server rejected despite looking fresh is refreshed on the next call.
    @Test
    func rejectedTokenRefreshesNextTime() async {
        let clock = Clock()
        let storage = MemoryStorage(ArtiseIDTokens(accessToken: "at-1", refreshToken: "rt-1", expiresAt: clock.now.addingTimeInterval(3600)))
        var answers = Self.answers
        answers[Self.token] = .init(body: #"{"access_token":"at-2","expires_in":43200,"refresh_token":"rt-2"}"#)
        let keeper = ArtiseIDTokenKeeper(client: ArtiseIDClient(transport: FakeTransport(answers), now: { clock.now }), storage: storage, now: { clock.now })
        await keeper.accessTokenRejected("someone-else")
        #expect(await keeper.accessToken() == .success("at-1"))
        await keeper.accessTokenRejected("at-1")
        #expect(await keeper.accessToken() == .success("at-2"))
    }
    
    /// Forgetting removes the tokens and gives the refresh token back to Artise ID.
    @Test
    func forgetRevokes() async {
        let clock = Clock()
        let storage = MemoryStorage(ArtiseIDTokens(accessToken: "at-1", refreshToken: "rt-1", expiresAt: clock.now.addingTimeInterval(3600)))
        var answers = Self.answers
        answers["https://id.artise.co/.well-known/openid-configuration"] = .init(body: ArtiseIDTests.discoveryWithRevocation)
        answers[Self.revoke] = .init(body: "")
        let transport = FakeTransport(answers)
        let keeper = ArtiseIDTokenKeeper(client: ArtiseIDClient(transport: transport, now: { clock.now }), storage: storage, now: { clock.now })
        await keeper.forget()
        #expect(storage.tokens == nil)
        #expect(await !keeper.hasTokens)
        let request = transport.requests.last
        #expect(request?.url?.absoluteString == Self.revoke)
        #expect(request?.httpMethod == "POST")
        #expect(String(decoding: request?.httpBody ?? Data(), as: UTF8.self)
            == "client_id=395423549856219219&token=rt-1&token_type_hint=refresh_token")
    }
}

/// Tokens in memory, standing in for the Keychain.
final class MemoryStorage: ArtiseIDTokenStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ArtiseIDTokens?
    
    init(_ tokens: ArtiseIDTokens?) {
        value = tokens
    }
    
    var tokens: ArtiseIDTokens? {
        lock.withLock { value }
    }
    
    func load() -> ArtiseIDTokens? {
        lock.withLock { value }
    }
    
    func save(_ tokens: ArtiseIDTokens) {
        lock.withLock { value = tokens }
    }
    
    func remove() {
        lock.withLock { value = nil }
    }
}
