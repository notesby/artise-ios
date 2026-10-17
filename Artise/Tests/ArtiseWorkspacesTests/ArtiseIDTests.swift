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

struct ArtiseIDTests {
    static let signIn = """
    {"issuer":"https://id.artise.co","client_id":"395423549856219219","redirect_uri":"https://join.artise.co/oauth",
     "scopes":["openid","profile","email"],"providers":{"apple":"111","google":"222","microsoft":"333","yahoo":"444"}}
    """
    static let discovery = """
    {"issuer":"https://id.artise.co","authorization_endpoint":"https://id.artise.co/oauth/v2/authorize",
     "token_endpoint":"https://id.artise.co/oauth/v2/token"}
    """
    static let tokens = #"{"access_token":"at-1","token_type":"Bearer","expires_in":43199,"refresh_token":"rt-1","id_token":"x"}"#
    static let list = """
    {"workspaces":[{"slug":"mas-k8s","name":"MAS test","server_name":"mas-k8s.artise.co","homeserver_url":"https://matrix.mas-k8s.artise.co"},
                   {"slug":"x","name":"","server_name":"not a server"}]}
    """
    
    /// The sign-in answer: issuer, client, return address, scopes and the providers the app knows.
    @Test
    func readsTheSignInAnswer() throws {
        let configuration = try #require(ArtiseIDConfiguration.parse(Data(Self.signIn.utf8)))
        #expect(configuration.issuer.absoluteString == "https://id.artise.co")
        #expect(configuration.clientID == "395423549856219219")
        #expect(configuration.redirectURL.absoluteString == "https://join.artise.co/oauth")
        #expect(configuration.scopes == ["openid", "profile", "email"])
        #expect(configuration.providers == [.apple: "111", .google: "222", .microsoft: "333"])
        #expect(configuration.scopes(for: .google) == ["openid", "profile", "email", "urn:zitadel:iam:org:idp:id:222"])
        #expect(configuration.scopes(for: nil) == ["openid", "profile", "email"])
    }
    
    /// An answer without an https issuer, a client or a return address on join.artise.co isn't used.
    /// api.artise.co's answer on 2026-10-17, verbatim: it reads, and each provider button opens its own provider.
    @Test
    func readsTheLiveSignInAnswer() throws {
        let live = #"{"issuer": "https://id.artise.co", "client_id": "395423549856219219", "redirect_uri": "https://join.artise.co/oauth", "scopes": ["openid", "profile", "email"], "providers": {"apple": "395419033345720907", "google": "395415843124544075", "microsoft": "395417126111805523"}}"#
        let configuration = try #require(ArtiseIDConfiguration.parse(Data(live.utf8)))
        #expect(configuration.providers.count == 3)
        #expect(configuration.scopes(for: .apple).last == "urn:zitadel:iam:org:idp:id:395419033345720907")
        let endpoints = try #require(ArtiseIDEndpoints.parse(Data(Self.discovery.utf8), issuer: configuration.issuer))
        #expect(endpoints.token.absoluteString == "https://id.artise.co/oauth/v2/token")
    }
    
    @Test
    func unusableSignInAnswers() {
        for body in [#"{"issuer":"http://id.artise.co","client_id":"1","redirect_uri":"https://join.artise.co/oauth"}"#,
                     #"{"issuer":"https://id.artise.co","redirect_uri":"https://join.artise.co/oauth"}"#,
                     #"{"issuer":"https://id.artise.co","client_id":"a b","redirect_uri":"https://join.artise.co/oauth"}"#,
                     #"{"issuer":"https://id.artise.co","client_id":"1","redirect_uri":"https://evil.example/oauth"}"#,
                     "<html>"] {
            #expect(ArtiseIDConfiguration.parse(Data(body.utf8)) == nil, "\(body)")
        }
    }
    
    /// 404 or no network: no Artise ID, so the app shows "type your workspace". A good answer is kept for an hour.
    @Test
    func signInAnswerIsCachedForAnHour() async {
        #expect(await ArtiseIDClient(transport: FakeTransport([:])).configuration() == nil)
        let missing = FakeTransport(["https://api.artise.co/v1/sign-in": .init(status: 404, body: "{}")])
        #expect(await ArtiseIDClient(transport: missing).configuration() == nil)
        
        let clock = Clock()
        let transport = FakeTransport(["https://api.artise.co/v1/sign-in": .init(body: Self.signIn)])
        let client = ArtiseIDClient(transport: transport, now: { clock.now })
        #expect(await client.configuration() != nil)
        #expect(await client.configuration() != nil)
        #expect(transport.requested.count == 1)
        clock.now += 3601
        _ = await client.configuration()
        #expect(transport.requested.count == 2)
    }
    
    /// The discovery document must be the issuer's, with https endpoints.
    @Test
    func discovery() throws {
        let issuer = try #require(URL(string: "https://id.artise.co"))
        let endpoints = try #require(ArtiseIDEndpoints.parse(Data(Self.discovery.utf8), issuer: issuer))
        #expect(endpoints.authorization.absoluteString == "https://id.artise.co/oauth/v2/authorize")
        #expect(endpoints.token.absoluteString == "https://id.artise.co/oauth/v2/token")
        #expect(ArtiseIDEndpoints.discoveryURL(issuer: issuer).absoluteString == "https://id.artise.co/.well-known/openid-configuration")
        let other = Self.discovery.replacingOccurrences(of: #""issuer":"https://id.artise.co""#, with: #""issuer":"https://evil.example""#)
        #expect(ArtiseIDEndpoints.parse(Data(other.utf8), issuer: issuer) == nil)
    }
    
    /// The sign-in page's address: code flow, PKCE S256, the state, and the provider's scope.
    @Test
    func authorizationURL() throws {
        let configuration = try #require(ArtiseIDConfiguration.parse(Data(Self.signIn.utf8)))
        let issuer = try #require(URL(string: "https://id.artise.co"))
        let endpoints = try #require(ArtiseIDEndpoints.parse(Data(Self.discovery.utf8), issuer: issuer))
        let authorization = try #require(ArtiseIDAuthorization(configuration: configuration, endpoints: endpoints, provider: .apple,
                                                               state: "state-1", verifier: "verifier-1", sha256: { _ in Data([0xFB, 0xFF]) }))
        let items = try #require(URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(authorization.url.absoluteString.hasPrefix("https://id.artise.co/oauth/v2/authorize?"))
        #expect(query == ["response_type": "code", "client_id": "395423549856219219", "redirect_uri": "https://join.artise.co/oauth",
                          "scope": "openid profile email urn:zitadel:iam:org:idp:id:111", "state": "state-1",
                          "code_challenge": "-_8", "code_challenge_method": "S256"])
    }
    
    #if canImport(CryptoKit)
    /// RFC 7636's example: the S256 challenge for its verifier.
    @Test
    func pkceChallenge() {
        #expect(PKCE.challenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    #endif
    
    /// Random tokens are valid PKCE verifiers (43 base64url characters) and differ each time.
    @Test
    func randomTokens() {
        let token = PKCE.randomToken()
        #expect(token.count == 43)
        #expect(token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        #expect(token != PKCE.randomToken())
    }
    
    /// Only a return carrying this attempt's state gives a code; a workspace's return or a refusal doesn't.
    @Test
    func callback() throws {
        let authorization = try makeAuthorization()
        let ok = try #require(URL(string: "https://join.artise.co/oauth?code=abc&state=state-1"))
        #expect(authorization.code(from: ok) == .success("abc"))
        let workspace = try #require(URL(string: "https://join.artise.co/oauth?code=abc&state=someone-else"))
        #expect(authorization.code(from: workspace) == .failure(.wrongState))
        let denied = try #require(URL(string: "https://join.artise.co/oauth?error=access_denied&state=state-1"))
        #expect(authorization.code(from: denied) == .failure(.cancelled))
        let broken = try #require(URL(string: "https://join.artise.co/oauth?state=state-1"))
        #expect(authorization.code(from: broken) == .failure(.refused))
    }
    
    /// The code is traded for tokens with the verifier and no secret; a refresh keeps the refresh token when none comes back.
    @Test
    func tokenExchangeAndRefresh() async throws {
        let configuration = try #require(ArtiseIDConfiguration.parse(Data(Self.signIn.utf8)))
        let endpoints = try #require(ArtiseIDEndpoints.parse(Data(Self.discovery.utf8), issuer: configuration.issuer))
        let clock = Clock()
        let transport = FakeTransport(["https://id.artise.co/oauth/v2/token": .init(body: Self.tokens)])
        let client = ArtiseIDClient(transport: transport, now: { clock.now })
        let tokens = try await client.tokens(code: "abc", authorization: makeAuthorization(), configuration: configuration, endpoints: endpoints).get()
        #expect(tokens == ArtiseIDTokens(accessToken: "at-1", refreshToken: "rt-1", expiresAt: clock.now.addingTimeInterval(43199)))
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let form = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(form == "client_id=395423549856219219&code=abc&code_verifier=verifier-1&grant_type=authorization_code&redirect_uri=https%3A%2F%2Fjoin.artise.co%2Foauth")
        #expect(tokens.isFresh(at: clock.now))
        #expect(!tokens.isFresh(at: clock.now.addingTimeInterval(43199 - 30)))
        
        let renewed = FakeTransport(["https://id.artise.co/oauth/v2/token": .init(body: #"{"access_token":"at-2","expires_in":60}"#)])
        let refreshed = try await ArtiseIDClient(transport: renewed, now: { clock.now }).refresh(tokens, configuration: configuration, endpoints: endpoints).get()
        #expect(refreshed.accessToken == "at-2")
        #expect(refreshed.refreshToken == "rt-1")
        let withoutRefresh = ArtiseIDTokens(accessToken: "a", refreshToken: nil, expiresAt: clock.now)
        #expect(await client.refresh(withoutRefresh, configuration: configuration, endpoints: endpoints) == .failure(.unauthorized))
        
        let refused = FakeTransport(["https://id.artise.co/oauth/v2/token": .init(status: 400, body: #"{"error":"invalid_grant"}"#)])
        let authorization = try makeAuthorization()
        #expect(await ArtiseIDClient(transport: refused).tokens(code: "x", authorization: authorization, configuration: configuration,
                                                                endpoints: endpoints) == .failure(.refused))
    }
    
    /// The person's workspaces, asked with the access token; entries without a valid server name are left out.
    @Test
    func workspaceList() async throws {
        let transport = FakeTransport(["https://api.artise.co/v1/me/workspaces": .init(body: Self.list)])
        let list = try await ArtiseIDClient(transport: transport).workspaces(accessToken: "at-1").get()
        #expect(list == [ArtiseIDWorkspace(slug: "mas-k8s", name: "MAS test", serverName: "mas-k8s.artise.co",
                                           homeserverURL: URL(string: "https://matrix.mas-k8s.artise.co"))])
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer at-1")
        
        let expired = FakeTransport(["https://api.artise.co/v1/me/workspaces": .init(status: 401, body: "{}")])
        #expect(await ArtiseIDClient(transport: expired).workspaces(accessToken: "old") == .failure(.unauthorized))
        #expect(await ArtiseIDClient(transport: FakeTransport([:])).workspaces(accessToken: "x") == .failure(.unreachable))
        let empty = FakeTransport(["https://api.artise.co/v1/me/workspaces": .init(body: #"{"workspaces":[]}"#)])
        #expect(await ArtiseIDClient(transport: empty).workspaces(accessToken: "x") == .success([]))
    }
    
    /// A listed workspace signs in with its file, or with the list's homeserver when the file can't be read.
    @Test
    func listedWorkspaceToSignIn() throws {
        let listed = ArtiseIDWorkspace(slug: "mas-k8s", name: "MAS test", serverName: "mas-k8s.artise.co",
                                       homeserverURL: URL(string: "https://matrix.mas-k8s.artise.co"))
        let withoutFile = listed.resolved(file: nil)
        #expect(withoutFile.serverName == "mas-k8s.artise.co")
        #expect(withoutFile.displayName == "MAS test")
        #expect(withoutFile.file?.homeserverURL?.absoluteString == "https://matrix.mas-k8s.artise.co")
        let file = try #require(WorkspaceFile.parse(Data(WorkspaceOAuthTests.wellKnown.utf8)))
        #expect(listed.resolved(file: file).branding?.oauth != nil)
    }
    
    private func makeAuthorization() throws -> ArtiseIDAuthorization {
        let configuration = try #require(ArtiseIDConfiguration.parse(Data(Self.signIn.utf8)))
        let endpoints = try #require(ArtiseIDEndpoints.parse(Data(Self.discovery.utf8), issuer: configuration.issuer))
        return try #require(ArtiseIDAuthorization(configuration: configuration, endpoints: endpoints, provider: nil,
                                                  state: "state-1", verifier: "verifier-1", sha256: { $0 }))
    }
}
