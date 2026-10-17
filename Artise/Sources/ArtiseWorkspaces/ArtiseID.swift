//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The sign-in providers Artise ID can open directly.
public enum ArtiseIDProvider: String, CaseIterable, Sendable {
    case apple, google, microsoft
}

/// How the apps sign in to Artise ID (`GET https://api.artise.co/v1/sign-in`).
public struct ArtiseIDConfiguration: Equatable, Sendable {
    public static let url = URL(staticString: "https://api.artise.co/v1/sign-in")
    
    public let issuer: URL
    public let clientID: String
    /// `https://join.artise.co/oauth`, the same return address as a workspace's sign-in.
    public let redirectURL: URL
    public let scopes: [String]
    /// Artise ID's id for each provider, for the scope that opens it directly.
    public let providers: [ArtiseIDProvider: String]
    /// Artise ID's own page for the password, passkeys and second steps.
    public var securityURL: URL?
    public var minimumAppVersion: MinimumAppVersion?
    public var storeLinks: StoreLinks?
    
    /// `nil` unless the answer has an https issuer, a client ID and a return address the app can receive.
    public static func parse(_ data: Data) -> ArtiseIDConfiguration? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let issuer = (object["issuer"] as? String).flatMap(WorkspaceURL.https),
              let clientID = object["client_id"] as? String, ArtiseIDText.isToken(clientID),
              let redirectURL = (object["redirect_uri"] as? String).flatMap(WorkspaceURL.https),
              redirectURL.host?.lowercased() == WorkspaceOAuthClient.redirectHost else {
            return nil
        }
        let scopes = (object["scopes"] as? [Any])?.compactMap { $0 as? String }.filter(ArtiseIDText.isToken) ?? []
        let providers = (object["providers"] as? [String: Any] ?? [:]).reduce(into: [ArtiseIDProvider: String]()) { providers, entry in
            if let provider = ArtiseIDProvider(rawValue: entry.key), let id = entry.value as? String, ArtiseIDText.isToken(id) {
                providers[provider] = id
            }
        }
        return ArtiseIDConfiguration(issuer: issuer, clientID: clientID, redirectURL: redirectURL,
                                     scopes: scopes.isEmpty ? ["openid"] : scopes, providers: providers,
                                     securityURL: (object["security_url"] as? String).flatMap(WorkspaceURL.https)
                                         .flatMap { ArtiseIDText.sameHost($0, issuer) ? $0 : nil },
                                     minimumAppVersion: MinimumAppVersion(value: object["min_app_version"]),
                                     storeLinks: StoreLinks(value: object["store_links"]))
    }
    
    /// Whether the tokens can be renewed without a new sign-in.
    public var asksForRefreshTokens: Bool {
        scopes.contains("offline_access")
    }
    
    /// The scopes to ask for: Artise's, plus the one that opens a provider directly (none for "Continue with email").
    public func scopes(for provider: ArtiseIDProvider?) -> [String] {
        guard let provider, let id = providers[provider] else { return scopes }
        return scopes + ["urn:zitadel:iam:org:idp:id:\(id)"]
    }
}

/// The issuer's OpenID discovery document: where to sign in and where to get tokens.
public struct ArtiseIDEndpoints: Equatable, Sendable {
    public let authorization: URL
    public let token: URL
    /// Where a refresh token is given back at the last sign-out; `nil` when the issuer doesn't say.
    public var revocation: URL?
    
    public static func discoveryURL(issuer: URL) -> URL {
        issuer.appendingPathComponent(".well-known/openid-configuration")
    }
    
    /// `nil` unless the document is for this issuer and both endpoints are https.
    public static func parse(_ data: Data, issuer: URL) -> ArtiseIDEndpoints? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let documentIssuer = (object["issuer"] as? String).flatMap(WorkspaceURL.https),
              ArtiseIDText.sameIssuer(documentIssuer, issuer),
              let authorization = (object["authorization_endpoint"] as? String).flatMap(WorkspaceURL.https),
              let token = (object["token_endpoint"] as? String).flatMap(WorkspaceURL.https) else {
            return nil
        }
        let revocation = (object["revocation_endpoint"] as? String).flatMap(WorkspaceURL.https)
        return ArtiseIDEndpoints(authorization: authorization, token: token,
                                 revocation: revocation.flatMap { ArtiseIDText.sameHost($0, issuer) ? $0 : nil })
    }
}

/// One sign-in attempt: authorization code with PKCE (S256). The state tells its return apart from a workspace's.
public struct ArtiseIDAuthorization: Sendable {
    public let state: String
    public let verifier: String
    public let url: URL
    
    public init?(configuration: ArtiseIDConfiguration, endpoints: ArtiseIDEndpoints, provider: ArtiseIDProvider?,
                 state: String = PKCE.randomToken(), verifier: String = PKCE.randomToken(),
                 sha256: (Data) -> Data = PKCE.sha256) {
        guard var components = URLComponents(url: endpoints.authorization, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURL.absoluteString),
            URLQueryItem(name: "scope", value: configuration.scopes(for: provider).joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(verifier: verifier, sha256: sha256)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        // "+" isn't escaped by URLComponents but means a space in a query.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { return nil }
        self.state = state
        self.verifier = verifier
        self.url = url
    }
    
    /// The code from Artise ID's return, only when it answers this attempt.
    public func code(from callback: URL) -> Result<String, ArtiseIDError> {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard value("state") == state else { return .failure(.wrongState) }
        if let error = value("error") {
            return .failure(error == "access_denied" ? .cancelled : .refused)
        }
        guard let code = value("code"), !code.isEmpty else { return .failure(.refused) }
        return .success(code)
    }
}

public enum ArtiseIDError: Error, Equatable, Sendable {
    /// The person closed the sign-in page.
    case cancelled
    /// A return for another sign-in (or none of ours).
    case wrongState
    /// Artise ID refused the sign-in or its tokens.
    case refused
    /// No answer, or one the app can't read.
    case unreachable
    /// The access token isn't valid any more.
    case unauthorized
    /// Artise's server doesn't offer this yet (404).
    case notAvailable
}

/// How the person's Artise ID sign-in is protected (`GET https://api.artise.co/v1/me/security`).
public struct ArtiseIDSecurity: Equatable, Sendable {
    public static let url = URL(staticString: "https://api.artise.co/v1/me/security")
    
    /// A second step is set up: an authenticator app, an email code or a security key. A passkey alone isn't one.
    public let twoStep: Bool
    /// The second steps Artise ID offers, best first: `passkey`, `totp`, `email`.
    public let methods: [String]
    /// Google, Microsoft or Apple when the person signs in with them; `nil` for an Artise ID password or passkey.
    public let provider: ArtiseIDProvider?
    
    public init(twoStep: Bool, methods: [String], provider: ArtiseIDProvider?) {
        self.twoStep = twoStep
        self.methods = methods
        self.provider = provider
    }
    
    static func parse(_ data: Data) -> ArtiseIDSecurity? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let twoStep = object["two_step"] as? Bool else {
            return nil
        }
        return ArtiseIDSecurity(twoStep: twoStep,
                                methods: (object["methods"] as? [Any])?.compactMap { $0 as? String } ?? [],
                                provider: (object["provider"] as? String).flatMap(ArtiseIDProvider.init(rawValue:)))
    }
}

/// Proof Key for Code Exchange (RFC 7636).
public enum PKCE {
    /// 32 random bytes, base64url: a valid verifier and a hard-to-guess state.
    public static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }
    
    public static func challenge(verifier: String, sha256: (Data) -> Data = sha256) -> String {
        base64URL(sha256(Data(verifier.utf8)))
    }
    
    public static func sha256(_ data: Data) -> Data {
        #if canImport(CryptoKit)
        Data(SHA256.hash(data: data))
        #else
        preconditionFailure("SHA-256 needs CryptoKit; pass a hash function on this platform.")
        #endif
    }
    
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Artise ID's tokens. Kept only to read the person's workspaces again.
public struct ArtiseIDTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    
    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
    
    /// A token answer; a refresh that doesn't send a new refresh token keeps the old one.
    static func parse(_ data: Data, now: Date, previousRefreshToken: String? = nil) -> ArtiseIDTokens? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let accessToken = object["access_token"] as? String, !accessToken.isEmpty,
              (object["token_type"] as? String)?.lowercased() ?? "bearer" == "bearer" else {
            return nil
        }
        let lifetime = (object["expires_in"] as? NSNumber)?.doubleValue ?? 300
        return ArtiseIDTokens(accessToken: accessToken,
                              refreshToken: (object["refresh_token"] as? String) ?? previousRefreshToken,
                              expiresAt: now.addingTimeInterval(lifetime))
    }
    
    /// Still usable for a minute or more.
    public func isFresh(at now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) > 60
    }
}

/// A workspace the person belongs to (`GET /v1/me/workspaces`).
public struct ArtiseIDWorkspace: Equatable, Sendable, Identifiable {
    public static let listURL = URL(staticString: "https://api.artise.co/v1/me/workspaces")
    
    public let slug: String?
    public let name: String
    public let serverName: String
    public let homeserverURL: URL?
    
    public var id: String {
        serverName
    }
    
    public init(slug: String?, name: String, serverName: String, homeserverURL: URL?) {
        self.slug = slug
        self.name = name
        self.serverName = serverName
        self.homeserverURL = homeserverURL
    }
    
    /// The list; entries without a valid server name are left out. `nil` when the answer can't be read.
    static func parseList(_ data: Data) -> [ArtiseIDWorkspace]? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = object["workspaces"] as? [Any] else {
            return nil
        }
        return entries.compactMap { entry in
            guard let entry = entry as? [String: Any],
                  case .serverName(let serverName)? = (entry["server_name"] as? String).flatMap(WorkspaceAddress.init(input:)) else {
                return nil
            }
            let slug = (entry["slug"] as? String).flatMap { WorkspaceSlug.isValid($0) ? $0 : nil }
            let name = (entry["name"] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return ArtiseIDWorkspace(slug: slug, name: name.flatMap { $0.isEmpty ? nil : $0 } ?? slug ?? serverName,
                                     serverName: serverName,
                                     homeserverURL: (entry["homeserver_url"] as? String).flatMap(WorkspaceURL.https))
        }
    }
    
    /// The workspace to sign in to, with its workspace file when it could be read.
    public func resolved(file: WorkspaceFile?) -> ResolvedWorkspace {
        let fallback = homeserverURL.map { WorkspaceFile(homeserverURL: $0, branding: nil) }
        let file = file.map { WorkspaceFile(homeserverURL: $0.homeserverURL ?? homeserverURL, branding: $0.branding) } ?? fallback
        return ResolvedWorkspace(slug: slug, serverName: serverName, directoryName: name, file: file)
    }
}

/// Talks to Artise ID and to Artise's list of the person's workspaces.
public actor ArtiseIDClient {
    private let transport: WorkspaceHTTPTransport
    private let now: @Sendable () -> Date
    private var configuration: (value: ArtiseIDConfiguration, expiry: Date)?
    private var endpoints: (issuer: URL, value: ArtiseIDEndpoints, expiry: Date)?
    
    /// How long the sign-in answer and the discovery document are kept.
    static let cacheLifetime: TimeInterval = 3600
    
    public init(transport: WorkspaceHTTPTransport = URLSessionWorkspaceTransport(), now: @escaping @Sendable () -> Date = { .now }) {
        self.transport = transport
        self.now = now
    }
    
    /// How to sign in to Artise ID, kept for an hour; `nil` when it's missing (404) or unreachable: the app then
    /// shows the "type your workspace" screen.
    public func configuration() async -> ArtiseIDConfiguration? {
        if let configuration, configuration.expiry > now() {
            return configuration.value
        }
        var request = URLRequest(url: ArtiseIDConfiguration.url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 6 // The first screen waits for it.
        guard let (body, response) = try? await transport.send(request), response.statusCode == 200,
              let value = ArtiseIDConfiguration.parse(body) else {
            return nil
        }
        configuration = (value, now().addingTimeInterval(Self.cacheLifetime))
        return value
    }
    
    /// The issuer's endpoints, kept for an hour.
    public func endpoints(for configuration: ArtiseIDConfiguration) async -> ArtiseIDEndpoints? {
        if let endpoints, endpoints.issuer == configuration.issuer, endpoints.expiry > now() {
            return endpoints.value
        }
        guard let (body, response) = try? await transport.get(ArtiseIDEndpoints.discoveryURL(issuer: configuration.issuer)),
              response.statusCode == 200,
              let value = ArtiseIDEndpoints.parse(body, issuer: configuration.issuer) else {
            return nil
        }
        endpoints = (configuration.issuer, value, now().addingTimeInterval(Self.cacheLifetime))
        return value
    }
    
    /// Trades the returned code for tokens (public client: no secret, the PKCE verifier instead).
    public func tokens(code: String, authorization: ArtiseIDAuthorization, configuration: ArtiseIDConfiguration,
                       endpoints: ArtiseIDEndpoints) async -> Result<ArtiseIDTokens, ArtiseIDError> {
        await tokenRequest(endpoints.token, form: ["grant_type": "authorization_code", "code": code,
                                                   "redirect_uri": configuration.redirectURL.absoluteString,
                                                   "client_id": configuration.clientID, "code_verifier": authorization.verifier],
                           previousRefreshToken: nil)
    }
    
    public func refresh(_ tokens: ArtiseIDTokens, configuration: ArtiseIDConfiguration,
                        endpoints: ArtiseIDEndpoints) async -> Result<ArtiseIDTokens, ArtiseIDError> {
        guard let refreshToken = tokens.refreshToken else { return .failure(.unauthorized) }
        return await tokenRequest(endpoints.token, form: ["grant_type": "refresh_token", "refresh_token": refreshToken,
                                                          "client_id": configuration.clientID],
                                  previousRefreshToken: refreshToken)
    }
    
    /// The workspaces the person is in. Never kept on disk.
    public func workspaces(accessToken: String) async -> Result<[ArtiseIDWorkspace], ArtiseIDError> {
        await authorizedGet(ArtiseIDWorkspace.listURL, accessToken: accessToken, parse: ArtiseIDWorkspace.parseList)
    }
    
    /// Whether two-step verification is on, and how the person signs in.
    public func security(accessToken: String) async -> Result<ArtiseIDSecurity, ArtiseIDError> {
        await authorizedGet(ArtiseIDSecurity.url, accessToken: accessToken, parse: ArtiseIDSecurity.parse)
    }
    
    /// Gives a refresh token back at the last sign-out, so it's refused from then on. Best effort: `false` when
    /// Artise ID couldn't be told.
    @discardableResult
    public func revoke(refreshToken: String, configuration: ArtiseIDConfiguration, endpoints: ArtiseIDEndpoints) async -> Bool {
        guard let url = endpoints.revocation else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(ArtiseIDText.formEncoded(["token": refreshToken, "token_type_hint": "refresh_token",
                                                          "client_id": configuration.clientID]).utf8)
        guard let (_, response) = try? await transport.send(request) else { return false }
        return response.statusCode == 200
    }
    
    private func authorizedGet<T>(_ url: URL, accessToken: String, parse: (Data) -> T?) async -> Result<T, ArtiseIDError> {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (body, response) = try? await transport.send(request) else { return .failure(.unreachable) }
        switch response.statusCode {
        case 200:
            return parse(body).map(Result.success) ?? .failure(.unreachable)
        case 401:
            return .failure(.unauthorized)
        case 404:
            return .failure(.notAvailable)
        default:
            return .failure(.unreachable)
        }
    }
    
    private func tokenRequest(_ url: URL, form: [String: String], previousRefreshToken: String?) async -> Result<ArtiseIDTokens, ArtiseIDError> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(ArtiseIDText.formEncoded(form).utf8)
        guard let (body, response) = try? await transport.send(request) else { return .failure(.unreachable) }
        guard response.statusCode == 200 else {
            return .failure((400..<500).contains(response.statusCode) ? .refused : .unreachable)
        }
        guard let tokens = ArtiseIDTokens.parse(body, now: now(), previousRefreshToken: previousRefreshToken) else {
            return .failure(.unreachable)
        }
        return .success(tokens)
    }
}

enum ArtiseIDText {
    /// Printable ASCII without spaces: client IDs, scopes, provider IDs.
    static func isToken(_ value: String) -> Bool {
        (1...255).contains(value.count) && value.unicodeScalars.allSatisfy { (0x21...0x7E).contains($0.value) }
    }
    
    static func sameHost(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.host?.lowercased() == rhs.host?.lowercased()
    }
    
    static func sameIssuer(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.absoluteString.trimmingSuffix("/") == rhs.absoluteString.trimmingSuffix("/")
    }
    
    static func formEncoded(_ form: [String: String]) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
