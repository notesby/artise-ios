//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import AuthenticationServices
import KeychainAccess
import SwiftUI

/// Signs in to Artise ID once, to list the person's workspaces. Its browser session is shared with the workspaces'
/// sign-in pages, so opening a workspace afterwards shows no page.
final class ArtiseIDSession {
    static let shared = ArtiseIDSession()
    
    let client: ArtiseIDClient
    /// The tokens, kept to read the list and the security settings again; given back when the person signs out.
    private let tokens: ArtiseIDTokenKeeper
    private var webSession: ArtiseIDWebSession?
    
    init() {
        client = ArtiseIDClient()
        tokens = ArtiseIDTokenKeeper(client: client, storage: ArtiseIDKeychainStorage())
    }
    
    /// How to sign in to Artise ID; `nil` when Artise ID isn't available, and the app offers "type your workspace".
    func configuration() async -> ArtiseIDConfiguration? {
        await client.configuration()
    }
    
    /// Whether the person signed in with Artise ID on this phone and it's still usable without a new sign-in.
    func hasTokens() async -> Bool {
        await tokens.hasTokens
    }
    
    /// The browser sign-in (straight to a provider, or Artise ID's own page), then the person's workspaces.
    func signIn(provider: ArtiseIDProvider?, window: UIWindow) async -> Result<[ArtiseIDWorkspace], ArtiseIDError> {
        switch await signInOnly(provider: provider, window: window) {
        case .success(let accessToken):
            return await client.workspaces(accessToken: accessToken)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// The browser sign-in alone, keeping the tokens; the access token on success.
    func signInOnly(provider: ArtiseIDProvider?, window: UIWindow) async -> Result<String, ArtiseIDError> {
        guard let configuration = await client.configuration(),
              let endpoints = await client.endpoints(for: configuration),
              let authorization = ArtiseIDAuthorization(configuration: configuration, endpoints: endpoints, provider: provider) else {
            return .failure(.unreachable)
        }
        let webSession = ArtiseIDWebSession(window: window)
        self.webSession = webSession
        defer { self.webSession = nil }
        
        guard let callback = await webSession.open(authorization.url, returningTo: configuration.redirectURL) else {
            return .failure(.cancelled)
        }
        let code: String
        switch authorization.code(from: callback) {
        case .success(let value):
            code = value
        case .failure(let error):
            MXLog.error("Artise ID sign-in didn't return a code: \(error)")
            return .failure(error)
        }
        switch await client.tokens(code: code, authorization: authorization, configuration: configuration, endpoints: endpoints) {
        case .success(let received):
            await tokens.keep(received)
            return .success(received.accessToken)
        case .failure(let error):
            MXLog.error("Artise ID tokens failed: \(error)")
            return .failure(error)
        }
    }
    
    /// Opens Artise ID's own page (password, passkeys, second steps) in the sign-in browser session, so it needs
    /// no new sign-in. Returns when the person closes it.
    func openSecurityPage(_ url: URL, window: UIWindow) async {
        guard let configuration = await client.configuration() else { return }
        let webSession = ArtiseIDWebSession(window: window)
        self.webSession = webSession
        defer { self.webSession = nil }
        _ = await webSession.open(url, returningTo: configuration.redirectURL)
    }
    
    /// The list again with the kept tokens, refreshed if needed; `nil` without usable tokens (sign in again).
    func workspacesAgain() async -> Result<[ArtiseIDWorkspace], ArtiseIDError>? {
        await withAccessToken { accessToken in await self.client.workspaces(accessToken: accessToken) }
    }
    
    /// Two-step verification and how the person signs in; `nil` without usable tokens (sign in again).
    func security() async -> Result<ArtiseIDSecurity, ArtiseIDError>? {
        await withAccessToken { accessToken in await self.client.security(accessToken: accessToken) }
    }
    
    /// Called when the person signs out of their last workspace, or picks another way to sign in.
    func forget() {
        Task { await tokens.forget() }
    }
    
    // MARK: - Private
    
    /// Runs `call` with a usable access token; after a 401, once more with a refreshed one.
    private func withAccessToken<T>(_ call: (String) async -> Result<T, ArtiseIDError>) async -> Result<T, ArtiseIDError>? {
        for attempt in 0..<2 {
            switch await tokens.accessToken() {
            case nil:
                return nil
            case .failure(let error):
                return .failure(error)
            case .success(let accessToken):
                let result = await call(accessToken)
                guard case .failure(.unauthorized) = result else { return result }
                await tokens.accessTokenRejected(accessToken)
                if attempt == 1 {
                    return nil
                }
            }
        }
        return nil
    }
}

/// The Artise ID tokens in the Keychain, on this phone only.
private struct ArtiseIDKeychainStorage: ArtiseIDTokenStorage {
    private static let service = "co.artise.app.artise-id"
    private static let key = "tokens"
    
    func load() -> ArtiseIDTokens? {
        guard let data = try? keychain.getData(Self.key) else { return nil }
        return try? JSONDecoder().decode(ArtiseIDTokens.self, from: data)
    }
    
    func save(_ tokens: ArtiseIDTokens) {
        do {
            try keychain.set(JSONEncoder().encode(tokens), key: Self.key)
        } catch {
            MXLog.error("Couldn't keep the Artise ID tokens: \(error)")
        }
    }
    
    func remove() {
        do {
            try keychain.remove(Self.key)
        } catch {
            MXLog.error("Couldn't delete the Artise ID tokens: \(error)")
        }
    }
    
    private var keychain: Keychain {
        Keychain(service: Self.service).accessibility(.afterFirstUnlockThisDeviceOnly)
    }
}

/// One Artise ID sign-in page. Not ephemeral: its cookies are the workspaces' sign-in pages' too.
private final class ArtiseIDWebSession: NSObject {
    private let window: UIWindow
    
    init(window: UIWindow) {
        self.window = window
    }
    
    /// The return URL, or `nil` when the person closed the page.
    func open(_ url: URL, returningTo redirectURL: URL) async -> URL? {
        guard let host = redirectURL.host() else { return nil }
        return await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .https(host: host, path: redirectURL.path())) { url, error in
                if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                    MXLog.error("Artise ID sign-in page failed: \(error)")
                }
                continuation.resume(returning: url)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            if !session.start() {
                continuation.resume(returning: nil)
            }
        }
    }
}

extension ArtiseIDWebSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}
