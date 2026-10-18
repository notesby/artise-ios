//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseWorkspaces
import Foundation
import Testing

struct WorkspaceAddressTests {
    /// Workspace names are trimmed and lower-cased before anything is sent.
    @Test
    func slugsAreTidied() {
        #expect(WorkspaceAddress(input: "  Acme ") == .slug("acme"))
        #expect(WorkspaceAddress(input: "artise") == .slug("artise"))
        #expect(WorkspaceAddress(input: "mi-taller-2") == .slug("mi-taller-2"))
    }
    
    /// Too short, too long, other characters, or hyphens at an end or doubled: not a workspace name.
    @Test
    func invalidSlugs() {
        for input in ["ab", "", "   ", String(repeating: "a", count: 31), "-acme", "acme-", "ac--me", "acme_co", "acmé", "ac me"] {
            #expect(WorkspaceAddress(input: input) == nil, "\(input)")
        }
        #expect(WorkspaceSlug.isValid("abc"))
        #expect(WorkspaceSlug.isValid(String(repeating: "a", count: 30)))
    }
    
    /// With a dot it's a server name, also when pasted as a web address or a Matrix ID.
    @Test
    func serverNames() {
        #expect(WorkspaceAddress(input: "artise.co") == .serverName("artise.co"))
        #expect(WorkspaceAddress(input: "Acme.Artise.co") == .serverName("acme.artise.co"))
        #expect(WorkspaceAddress(input: "https://acme.artise.co/") == .serverName("acme.artise.co"))
        #expect(WorkspaceAddress(input: "@ana:acme.artise.co") == .serverName("acme.artise.co"))
        #expect(WorkspaceAddress(input: "matrix.example.com:8448") == .serverName("matrix.example.com:8448"))
        #expect(WorkspaceAddress(input: "artise.co")?.text == "artise.co")
    }
    
    /// Broken server names are refused before any request.
    @Test
    func invalidServerNames() {
        for input in ["artise.", ".co", "a..co", "-a.co", "a.co:port", "a.co:70000", "acme artise.co", "a.co/x"] {
            #expect(WorkspaceAddress(input: input) == nil, "\(input)")
        }
    }
    
    /// An account's server comes from its Matrix ID.
    @Test
    func serverNameFromUserID() {
        #expect(WorkspaceHosts.serverName(userID: "@ana:acme.artise.co") == "acme.artise.co")
        #expect(WorkspaceHosts.serverName(userID: "@ana:Artise.co") == "artise.co")
        #expect(WorkspaceHosts.serverName(userID: "ana") == nil)
        #expect(WorkspaceHosts.serverName(userID: "@ana:") == nil)
    }
}
