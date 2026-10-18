//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A workspace's own Artise app client (`co.artise.workspace.oauth`). Its sign-in service knows it, so it skips the
/// "Continue to Artise" consent page.
public struct WorkspaceOAuthClient: Codable, Equatable, Sendable {
    /// The only host whose links this app may receive (Associated Domains: applinks and webcredentials).
    static let redirectHost = "join.artise.co"
    
    public let iosClientID: String
    /// `https://join.artise.co/oauth`.
    public let redirectURL: URL
    
    public init(iosClientID: String, redirectURL: URL) {
        self.iosClientID = iosClientID
        self.redirectURL = redirectURL
    }
    
    /// `nil` without a usable iOS client ID, or with a redirect this app can't receive.
    init?(section: [String: Any]) {
        guard let clientID = section["ios"] as? String,
              (1...255).contains(clientID.count),
              clientID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-._~".contains($0)) }),
              let redirectURL = (section["redirect_uri"] as? String).flatMap(WorkspaceURL.https),
              redirectURL.host?.lowercased() == Self.redirectHost,
              redirectURL.query == nil, redirectURL.fragment == nil else {
            return nil
        }
        self.init(iosClientID: clientID, redirectURL: redirectURL)
    }
}

/// How the app registers with a workspace's sign-in service.
public struct WorkspaceSignInClient: Equatable, Sendable {
    /// Where the sign-in page returns to the app.
    public let redirectURL: URL
    /// Issuer → client ID. Empty: the app registers itself (dynamic registration).
    public let staticRegistrations: [String: String]
    
    /// Dynamic registration, returning to the app's own scheme: workspaces without `oauth`.
    public static let dynamic = WorkspaceSignInClient(redirectURL: ArtiseConfiguration.oAuthRedirectURL, staticRegistrations: [:])
    
    /// The workspace's own client for its issuer, else dynamic registration.
    public static func client(for workspace: ResolvedWorkspace?, issuer: String?) -> WorkspaceSignInClient {
        guard let oauth = workspace?.branding?.oauth, let issuer, !issuer.isEmpty else { return .dynamic }
        return WorkspaceSignInClient(redirectURL: oauth.redirectURL, staticRegistrations: [issuer: oauth.iosClientID])
    }
}

/// The homeserver's OAuth server metadata, for its `issuer`: the key the Matrix SDK looks static clients up by.
enum AuthMetadata {
    static func urls(homeserverURL: URL) -> [URL] {
        ["_matrix/client/v1/auth_metadata", "_matrix/client/unstable/org.matrix.msc2965/auth_metadata"]
            .map { homeserverURL.appendingPathComponent($0) }
    }
    
    /// The `issuer`, exactly as the server wrote it (the SDK compares strings); only `https`.
    static func issuer(from data: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let issuer = object["issuer"] as? String,
              WorkspaceURL.https(issuer)?.absoluteString == issuer else {
            return nil
        }
        return issuer
    }
}

public extension WorkspaceClient {
    /// How to sign in to this workspace: its own client when its file has `oauth` and its server says who its
    /// issuer is, else dynamic registration.
    func signInClient(for workspace: ResolvedWorkspace) async -> WorkspaceSignInClient {
        guard workspace.branding?.oauth != nil, let homeserverURL = workspace.file?.homeserverURL else { return .dynamic }
        return await .client(for: workspace, issuer: issuer(homeserverURL: homeserverURL))
    }
    
    /// The sign-in service's issuer, from the stable endpoint or the older unstable one.
    func issuer(homeserverURL: URL) async -> String? {
        for url in AuthMetadata.urls(homeserverURL: homeserverURL) {
            if let issuer = await answer(url).flatMap(AuthMetadata.issuer(from:)) {
                return issuer
            }
        }
        return nil
    }
}
