//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseWorkspaces
import Foundation
import Testing

struct WorkspaceFileTests {
    /// Every field of a full section is read.
    @Test
    func fullFile() throws {
        let file = try #require(WorkspaceFile.parse(Data("""
        {"m.homeserver":{"base_url":"https://matrix.artise.co"},
         "org.matrix.msc4143.rtc_foci":[{"type":"livekit","livekit_service_url":"https://matrix.artise.co/livekit/jwt"}],
         "co.artise.workspace":{"version":1,"name":"Acme","logo":"https://acme.artise.co/brand/logo-abc.png",
          "colors":{"accent":"#1f6feb"},"assistant_name":"Nova","welcome":{"en":"Welcome to Acme","es":"Bienvenido"},
          "language":"es","features":["booking","tasks"],"push_gateway":"https://push.artise.co/_matrix/push/v1/notify"}}
        """.utf8)))
        #expect(file.homeserverURL?.absoluteString == "https://matrix.artise.co")
        let branding = try #require(file.branding)
        #expect(branding.name == "Acme")
        #expect(branding.logoURL?.absoluteString == "https://acme.artise.co/brand/logo-abc.png")
        #expect(branding.accentHex == "#1F6FEB")
        #expect(branding.assistantName == "Nova")
        #expect(branding.welcome == ["en": "Welcome to Acme", "es": "Bienvenido"])
        #expect(branding.language == "es")
        #expect(branding.features == ["booking", "tasks"])
        #expect(WorkspaceBranding.pushGatewayURL(for: branding).absoluteString == "https://push.artise.co/_matrix/push/v1/notify")
    }
    
    /// A partial section keeps what it has; the rest is Artise's default.
    @Test
    func partialSection() throws {
        let file = try #require(WorkspaceFile.parse(Data(#"{"m.homeserver":{"base_url":"https://matrix.acme.artise.co"},"co.artise.workspace":{"version":1,"name":"Acme"}}"#.utf8)))
        let branding = try #require(file.branding)
        #expect(branding.name == "Acme")
        #expect(branding.logoURL == nil && branding.accentHex == nil && branding.assistantName == nil)
        #expect(branding.features == nil)
        #expect(branding.shows(feature: "booking"))
    }
    
    /// No section: sign-in works with Artise's look.
    @Test
    func missingSection() throws {
        let file = try #require(WorkspaceFile.parse(Data(#"{"m.homeserver":{"base_url":"https://matrix.artise.co"}}"#.utf8)))
        #expect(file.homeserverURL != nil)
        #expect(file.branding == nil)
        #expect(WorkspaceBranding.pushGatewayURL(for: file.branding) == WorkspaceBranding.defaultPushGatewayURL)
        #expect(WorkspaceFile.parse(Data("not json".utf8)) == nil)
        #expect(WorkspaceFile.parse(Data("[1,2]".utf8)) == nil)
    }
    
    /// Malformed values are dropped one by one: wrong types, bad colours, links that aren't https, empty names.
    @Test
    func malformedValues() throws {
        let file = try #require(WorkspaceFile.parse(Data("""
        {"m.homeserver":{"base_url":"http://matrix.acme.example"},
         "co.artise.workspace":{"name":"  ","logo":"javascript:alert(1)","colors":{"accent":"blue"},"assistant_name":42,
          "welcome":"hi","features":"booking","push_gateway":"http://push.example/notify","language":"es"}}
        """.utf8)))
        #expect(file.homeserverURL == nil)
        let branding = try #require(file.branding)
        #expect(branding == WorkspaceBranding(language: "es"))
        #expect(WorkspaceBranding.pushGatewayURL(for: branding) == WorkspaceBranding.defaultPushGatewayURL)
        #expect(WorkspaceFile.parse(Data(#"{"co.artise.workspace":"Acme"}"#.utf8))?.branding == nil)
    }
    
    /// A newer version with fields the app doesn't know: the known ones still apply.
    @Test
    func newerVersion() throws {
        let file = try #require(WorkspaceFile.parse(Data("""
        {"co.artise.workspace":{"version":2,"name":"Acme","colors":{"accent":"1F6FEB","background":"#000000"},"themes":{"x":1}}}
        """.utf8)))
        #expect(file.branding?.name == "Acme")
        #expect(file.branding?.accentHex == "#1F6FEB")
    }
    
    /// The welcome line: the phone's language, then the workspace's, else none.
    @Test
    func welcomeLanguage() {
        let branding = WorkspaceBranding(welcome: ["en": "Welcome", "es": "Bienvenido"], language: "es")
        #expect(branding.welcomeText(preferredLanguages: ["en-US"]) == "Welcome")
        #expect(branding.welcomeText(preferredLanguages: ["es-MX", "en"]) == "Bienvenido")
        #expect(branding.welcomeText(preferredLanguages: ["fr-FR"]) == "Bienvenido")
        #expect(WorkspaceBranding(welcome: ["pt": "Bem-vindo"], language: "es").welcomeText(preferredLanguages: ["fr"]) == nil)
    }
    
    /// A screen hides only when the server lists features and its own isn't there.
    @Test
    func features() {
        let branding = WorkspaceBranding(features: ["booking"])
        #expect(branding.shows(feature: "booking"))
        #expect(!branding.shows(feature: "tasks"))
        #expect(WorkspaceBranding().shows(feature: "tasks"))
    }
    
    /// The workspace's assistant name replaces "Ari" as a whole word only.
    @Test
    func assistantName() {
        let branding = WorkspaceBranding(assistantName: "Nova")
        #expect(branding.naming("Ask Ari to save something, like “Ari, note…”") == "Ask Nova to save something, like “Nova, note…”")
        #expect(branding.naming("Arizona and Marina") == "Arizona and Marina")
        #expect(WorkspaceBranding().naming("Ari") == "Ari")
    }
    
    /// The push gateway: the workspace's, else the shared one; never a plain-http address.
    @Test
    func pushGatewayChoice() {
        let custom = URL(string: "https://push.acme.example/_matrix/push/v1/notify")
        #expect(WorkspaceBranding.pushGatewayURL(for: WorkspaceBranding(pushGatewayURL: custom)) == custom)
        #expect(WorkspaceBranding.pushGatewayURL(for: nil).absoluteString == "https://push.artise.co/_matrix/push/v1/notify")
    }
    
    /// `links` gives the web app's full URLs; a link that isn't https is dropped, and no usable link means none.
    @Test
    func links() throws {
        let file = try #require(WorkspaceFile.parse(Data("""
        {"co.artise.workspace":{"links":{"web":"https://chat.acme.example","notes_api":"https://chat.acme.example/api/notes/v1",
         "delete_account":"http://chat.acme.example/account/delete","calendar":"https://cal.acme.example"}}}
        """.utf8)))
        #expect(file.branding?.links == WorkspaceLinks(web: URL(string: "https://chat.acme.example"),
                                                       notesAPI: URL(string: "https://chat.acme.example/api/notes/v1")))
        #expect(WorkspaceFile.parse(Data(#"{"co.artise.workspace":{"links":{"web":"ftp://x"}}}"#.utf8))?.branding?.links == nil)
        #expect(WorkspaceFile.parse(Data(#"{"co.artise.workspace":{"links":"https://chat.acme.example"}}"#.utf8))?.branding?.links == nil)
    }
    
    /// Without `links` a workspace has no notes or delete page, and nothing is guessed from its server name;
    /// only artise.co falls back to chat.artise.co until its file has them.
    @Test
    func linksFallbackOnlyForArtise() {
        let acme = ResolvedWorkspace(slug: "acme", serverName: "acme.artise.co", directoryName: "Acme",
                                     file: WorkspaceFile(homeserverURL: nil, branding: WorkspaceBranding(name: "Acme")))
        #expect(WorkspaceLinks.links(for: acme) == nil)
        #expect(WorkspaceLinks.links(for: nil) == nil)
        
        let artise = ResolvedWorkspace(slug: "artise", serverName: "artise.co", directoryName: "Artise", file: nil)
        #expect(WorkspaceLinks.links(for: artise)?.notesAPI?.absoluteString == "https://chat.artise.co/api/notes/v1")
        #expect(WorkspaceLinks.links(for: artise)?.deleteAccount?.absoluteString == "https://chat.artise.co/account/delete")
        
        let published = WorkspaceLinks(notesAPI: URL(string: "https://web.acme.example/api/notes/v1"))
        let acmeWithLinks = ResolvedWorkspace(slug: "acme", serverName: "acme.artise.co", directoryName: "Acme",
                                              file: WorkspaceFile(homeserverURL: nil, branding: WorkspaceBranding(links: published)))
        #expect(WorkspaceLinks.links(for: acmeWithLinks) == published)
    }
}
