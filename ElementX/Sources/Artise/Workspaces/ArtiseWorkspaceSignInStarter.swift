//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import SwiftUI

/// Gets a workspace ready to sign in to, from "Your workspace" or from the list of the person's workspaces:
/// Element's login is set up for its server, then a password form or its sign-in page with its own app client.
struct ArtiseWorkspaceSignInStarter {
    enum Outcome {
        case password
        case oAuth(data: OAuthAuthorizationDataProxy, window: UIWindow)
        case failed(message: String)
    }
    
    let authenticationService: AuthenticationServiceProtocol
    let authenticationFlow: AuthenticationFlow
    let appSettings: AppSettings
    
    func start(_ workspace: ResolvedWorkspace, address: WorkspaceAddress, window: UIWindow?) async -> Outcome {
        guard await configure(for: workspace) else {
            MXLog.error("Sign-in isn't available for workspace server \(workspace.serverName)")
            return .failed(message: String(format: ArtiseWorkspacesL10n.text("screen_workspace_error_sign_in_unavailable"),
                                           workspace.displayName ?? workspace.serverName))
        }
        ArtiseWorkspaces.shared.didChoose(workspace, address: address)
        guard authenticationService.homeserver.value.loginMode.supportsOAuthFlow else { return .password }
        
        // The workspace's own app client skips the sign-in page's "Continue to Artise" consent.
        let client = await ArtiseWorkspaces.shared.client.signInClient(for: workspace)
        appSettings.artiseUseOAuthClient(redirectURL: client.redirectURL,
                                         staticRegistrations: client.staticRegistrations.reduce(into: [:]) { registrations, entry in
                                             if let issuer = URL(string: entry.key) {
                                                 registrations[issuer] = entry.value
                                             }
                                         })
        guard let window else {
            MXLog.error("No window available for OAuth presentation")
            return .failed(message: L10n.errorUnknown)
        }
        switch await authenticationService.urlForOAuthLogin(loginHint: nil) {
        case .success(let data):
            return .oAuth(data: data, window: window)
        case .failure(let error):
            MXLog.error("Failed to get OAuth login URL: \(error)")
            return .failed(message: L10n.errorUnknown)
        }
    }
    
    /// The server's own discovery first; the workspace file's address if that fails.
    private func configure(for workspace: ResolvedWorkspace) async -> Bool {
        if case .success = await authenticationService.configure(for: workspace.serverName, flow: authenticationFlow) {
            return true
        }
        guard let homeserverURL = workspace.file?.homeserverURL else { return false }
        if case .success = await authenticationService.configure(for: homeserverURL.absoluteString, flow: authenticationFlow) {
            return true
        }
        return false
    }
}
