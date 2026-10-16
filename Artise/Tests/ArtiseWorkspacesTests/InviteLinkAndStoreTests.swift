//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseWorkspaces
import Foundation
import Testing

struct InviteLinkAndStoreTests {
    let defaults = UserDefaults(suiteName: "artise-tests-\(UUID().uuidString)") ?? .standard
    
    /// `https://join.artise.co/{slug}/{code}` gives the workspace and the code.
    @Test
    func inviteLinks() throws {
        let link = try #require(invite("https://join.artise.co/Acme/Ab_3-xYz9"))
        #expect(link.slug == "acme")
        #expect(link.code == "Ab_3-xYz9")
        #expect(invite("https://join.artise.co/acme/Ab3xYz9/") != nil)
    }
    
    /// Other hosts, schemes, shapes, slugs or codes aren't invites.
    @Test
    func notInviteLinks() {
        for link in ["https://artise.co/acme/Ab3xYz9", "http://join.artise.co/acme/Ab3xYz9", "https://join.artise.co/acme",
                     "https://join.artise.co/acme/Ab3xYz9/more", "https://join.artise.co/ab/Ab3xYz9", "https://join.artise.co/acme/abc",
                     "https://join.artise.co/acme/" + String(repeating: "a", count: 65), "https://join.artise.co/acme/Ab3x%20Yz9"] {
            #expect(invite(link) == nil, "\(link)")
        }
    }
    
    /// A sign-in page returning to the app (`/oauth`, one segment) is never an invite.
    @Test
    func signInReturnIsNotAnInvite() {
        for link in ["https://join.artise.co/oauth?code=abcdef123456&state=Ab3xYz9", "https://join.artise.co/oauth",
                     "https://join.artise.co/oauth?error=access_denied"] {
            #expect(invite(link) == nil, "\(link)")
        }
    }
    
    /// The join page is the directory's `join_url` plus the code; before servers send it, the link itself.
    @Test
    func joinPage() throws {
        let link = try #require(invite("https://join.artise.co/acme/Ab3xYz9"))
        let withJoin = WorkspaceInfo(slug: "acme", name: "Acme", serverName: "acme.artise.co", homeserverURL: nil, isActive: true,
                                     joinURL: URL(string: "https://chat.acme.artise.co/join"))
        #expect(link.joinPageURL(for: withJoin).absoluteString == "https://chat.acme.artise.co/join/Ab3xYz9")
        let withoutJoin = WorkspaceInfo(slug: "acme", name: "Acme", serverName: "acme.artise.co", homeserverURL: nil, isActive: true, joinURL: nil)
        #expect(link.joinPageURL(for: withoutJoin) == link.url)
    }
    
    /// The directory's `join_url` is read when present.
    @Test
    func joinURLFromDirectory() {
        let body = Data(#"{"slug":"acme","name":"Acme","server_name":"acme.artise.co","status":"active","join_url":"https://chat.acme.artise.co/join","plan":"pro"}"#.utf8)
        guard case .found(let info) = WorkspaceDirectory.result(statusCode: 200, retryAfter: nil, body: body) else {
            Issue.record("Expected an active workspace")
            return
        }
        #expect(info.joinURL?.absoluteString == "https://chat.acme.artise.co/join")
    }
    
    /// Each server's workspace is kept until its account signs out; the last address prefills the field.
    @Test
    func storeKeepsWorkspaces() {
        let store = WorkspaceStore(defaults: defaults)
        let acme = ResolvedWorkspace(slug: "acme", serverName: "acme.artise.co", directoryName: "Acme",
                                     file: WorkspaceFile(homeserverURL: nil, branding: WorkspaceBranding(name: "Acme Inc")))
        store.save(acme)
        store.lastAddress = "acme"
        #expect(WorkspaceStore(defaults: defaults).workspace(serverName: "Acme.artise.co") == acme)
        #expect(WorkspaceStore(defaults: defaults).lastAddress == "acme")
        store.remove(serverName: "acme.artise.co")
        #expect(store.workspace(serverName: "acme.artise.co") == nil)
    }
    
    /// The welcome shows once, for the first session on the server where sign-in started.
    @Test
    func welcomeShowsOnce() {
        let store = WorkspaceStore(defaults: defaults)
        #expect(!store.consumeWelcome(serverName: "acme.artise.co"))
        store.markWelcomePending(serverName: "acme.artise.co")
        #expect(!store.consumeWelcome(serverName: "artise.co"))
        #expect(store.consumeWelcome(serverName: "acme.artise.co"))
        #expect(!store.consumeWelcome(serverName: "acme.artise.co"))
    }
    
    private func invite(_ link: String) -> InviteLink? {
        URL(string: link).flatMap(InviteLink.init(url:))
    }
}
