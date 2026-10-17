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
    
    let client = ArtiseIDClient()
    /// The tokens, only to read the list again; deleted when the person signs out.
    private let keychain = Keychain(service: "co.artise.app.artise-id").accessibility(.afterFirstUnlockThisDeviceOnly)
    private let tokensKey = "tokens"
    private var webSession: ArtiseIDWebSession?
    
    /// How to sign in to Artise ID; `nil` when Artise ID isn't available, and the app offers "type your workspace".
    func configuration() async -> ArtiseIDConfiguration? {
        await client.configuration()
    }
    
    /// The browser sign-in (straight to a provider, or Artise ID's own page), then the person's workspaces.
    func signIn(provider: ArtiseIDProvider?, window: UIWindow) async -> Result<[ArtiseIDWorkspace], ArtiseIDError> {
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
        case .success(let tokens):
            save(tokens)
            return await client.workspaces(accessToken: tokens.accessToken)
        case .failure(let error):
            MXLog.error("Artise ID tokens failed: \(error)")
            return .failure(error)
        }
    }
    
    /// The list again with the kept tokens, refreshed if needed; `nil` without usable tokens (sign in again).
    func workspacesAgain() async -> Result<[ArtiseIDWorkspace], ArtiseIDError>? {
        guard var tokens = savedTokens() else { return nil }
        if !tokens.isFresh(at: .now) {
            guard let configuration = await client.configuration(), let endpoints = await client.endpoints(for: configuration),
                  case .success(let refreshed) = await client.refresh(tokens, configuration: configuration, endpoints: endpoints) else {
                forget()
                return nil
            }
            tokens = refreshed
            save(tokens)
        }
        let result = await client.workspaces(accessToken: tokens.accessToken)
        if result == .failure(.unauthorized) {
            forget()
            return nil
        }
        return result
    }
    
    /// Called when the person signs out of their (only) workspace.
    func forget() {
        do {
            try keychain.remove(tokensKey)
        } catch {
            MXLog.error("Couldn't delete the Artise ID tokens: \(error)")
        }
    }
    
    // MARK: - Private
    
    private func save(_ tokens: ArtiseIDTokens) {
        do {
            try keychain.set(JSONEncoder().encode(tokens), key: tokensKey)
        } catch {
            MXLog.error("Couldn't keep the Artise ID tokens: \(error)")
        }
    }
    
    private func savedTokens() -> ArtiseIDTokens? {
        guard let data = try? keychain.getData(tokensKey) else { return nil }
        return try? JSONDecoder().decode(ArtiseIDTokens.self, from: data)
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
