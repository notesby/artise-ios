//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// What the app remembers about workspaces on this phone: the last one typed, each account's workspace
/// (kept per server, so a second account can come later), and which welcomes were shown.
public struct WorkspaceStore {
    private static let lastAddressKey = "co.artise.workspaces.lastAddress"
    private static let workspacesKey = "co.artise.workspaces.byServer"
    private static let pendingWelcomeKey = "co.artise.workspaces.pendingWelcome"
    
    private let defaults: UserDefaults
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    /// What to prefill in "Your workspace".
    public var lastAddress: String? {
        get { defaults.string(forKey: Self.lastAddressKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.lastAddressKey) }
    }
    
    public func workspace(serverName: String) -> ResolvedWorkspace? {
        all()[serverName.lowercased()]
    }
    
    public func save(_ workspace: ResolvedWorkspace) {
        var workspaces = all()
        workspaces[workspace.serverName.lowercased()] = workspace
        write(workspaces)
    }
    
    /// Forgets a workspace when its account signs out.
    public func remove(serverName: String) {
        var workspaces = all()
        workspaces[serverName.lowercased()] = nil
        write(workspaces)
    }
    
    /// Sign-in to this server started from "Your workspace": its first session shows the welcome.
    public func markWelcomePending(serverName: String) {
        defaults.set(serverName.lowercased(), forKey: Self.pendingWelcomeKey)
    }
    
    /// Whether the session that just started on `serverName` is the first sign-in; true once.
    public func consumeWelcome(serverName: String) -> Bool {
        guard defaults.string(forKey: Self.pendingWelcomeKey) == serverName.lowercased() else { return false }
        defaults.removeObject(forKey: Self.pendingWelcomeKey)
        return true
    }
    
    private func all() -> [String: ResolvedWorkspace] {
        guard let data = defaults.data(forKey: Self.workspacesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: ResolvedWorkspace].self, from: data)) ?? [:]
    }
    
    private func write(_ workspaces: [String: ResolvedWorkspace]) {
        defaults.set(try? JSONEncoder().encode(workspaces), forKey: Self.workspacesKey)
    }
}

/// Where an account's workspace lives.
public enum WorkspaceHosts {
    /// `@ana:acme.artise.co` → `acme.artise.co`.
    public static func serverName(userID: String) -> String? {
        guard userID.hasPrefix("@"), let colon = userID.firstIndex(of: ":") else { return nil }
        let serverName = userID[userID.index(after: colon)...].lowercased()
        return serverName.isEmpty ? nil : serverName
    }
}
