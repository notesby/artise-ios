//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ElementX
import Testing

/// The workspace switcher: its list, what it says is already open, and when it asks the app to switch.
@MainActor
struct ArtiseWorkspaceSwitcherTests {
    /// Workspaces are listed by name (the server's name when the phone doesn't know the workspace), so rows stay put.
    @Test
    func listsWorkspacesByName() {
        let switcher = ArtiseWorkspaceSwitcher()
        switcher.update(userIDs: ["@ana:sol.example.org", "@ana:familia.example.org"], currentUserID: "@ana:sol.example.org")
        
        #expect(switcher.workspaces.map(\.userID) == ["@ana:familia.example.org", "@ana:sol.example.org"])
        #expect(switcher.currentUserID == "@ana:sol.example.org")
        #expect(!switcher.isLastWorkspace)
    }
    
    /// The Artise ID list marks a workspace whose server already has an account on this phone, whatever its case.
    @Test
    func findsTheAccountAlreadyOpenOnAServer() {
        let switcher = ArtiseWorkspaceSwitcher()
        switcher.update(userIDs: ["@ana:sol.example.org"], currentUserID: "@ana:sol.example.org")
        
        #expect(switcher.openUserID(serverName: "SOL.example.org") == "@ana:sol.example.org")
        #expect(switcher.openUserID(serverName: "familia.example.org") == nil)
        #expect(switcher.isLastWorkspace)
    }
    
    /// An invite link to a workspace already on this phone opens that account; any other adds the workspace.
    @Test
    func invitesFindTheAccountAlreadyInTheWorkspace() {
        let userIDs = ["@ana:sol.example.org", "@ana:familia.example.org"]
        
        #expect(ArtiseWorkspaces.userID(in: userIDs, serverName: "Familia.example.org") == "@ana:familia.example.org")
        #expect(ArtiseWorkspaces.userID(in: userIDs, serverName: "tienda.example.org") == nil)
        #expect(ArtiseWorkspaces.userID(in: [], serverName: "sol.example.org") == nil)
    }
    
    /// Picking the workspace on screen does nothing; another one, or any while adding, asks the app to switch.
    @Test
    func switchesOnlyToAnotherWorkspace() {
        let switcher = ArtiseWorkspaceSwitcher()
        var switched: [String] = []
        switcher.setUp { switched.append($0) } add: { } cancelAdding: { }
        switcher.update(userIDs: ["@ana:sol.example.org", "@ana:familia.example.org"], currentUserID: "@ana:sol.example.org")
        
        switcher.switchTo("@ana:sol.example.org")
        switcher.switchTo("@ana:familia.example.org")
        switcher.setAdding(true)
        switcher.switchTo("@ana:sol.example.org")
        
        #expect(switched == ["@ana:familia.example.org", "@ana:sol.example.org"])
    }
    
    /// The switcher's words read as sentences in each language, never as their keys.
    @Test(arguments: ["en", "es", "pt"])
    func hasItsWords(language: String) {
        for key in ["screen_artise_workspaces_title", "screen_artise_workspaces_add", "screen_artise_id_already_open",
                    "screen_workspace_error_already_open"] {
            #expect(ArtiseWorkspacesL10n.text(key, language: language) != key)
        }
    }
}
