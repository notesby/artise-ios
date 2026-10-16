//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseWorkspaces
import Foundation
import Testing

struct WorkspaceOAuthTests {
    static let oauth = #"{"ios":"01K7ARTSEAPP1PH0NE00000000","android":"01K7ARTSEAPPANDR0D00000000","redirect_uri":"https://join.artise.co/oauth"}"#
    static let wellKnown = #"{"m.homeserver":{"base_url":"https://matrix.mas-k8s.artise.co"},"co.artise.workspace":{"version":1,"name":"MAS","oauth":\#(oauth)}}"#
    static let metadata = #"{"issuer":"https://auth.mas-k8s.artise.co/","authorization_endpoint":"https://auth.mas-k8s.artise.co/authorize"}"#
    
    /// `oauth` gives the iOS client and its https return address; the Android client is ignored.
    @Test
    func readsTheClient() throws {
        let file = try #require(WorkspaceFile.parse(Data(Self.wellKnown.utf8)))
        let oauth = try #require(file.branding?.oauth)
        #expect(oauth.iosClientID == "01K7ARTSEAPP1PH0NE00000000")
        #expect(oauth.redirectURL.absoluteString == "https://join.artise.co/oauth")
    }
    
    /// A missing client ID, a return address that isn't https on join.artise.co, or a section of the wrong type:
    /// no static client, so sign-in keeps registering itself.
    @Test
    func unusableClientsAreIgnored() {
        let sections = [#"{"redirect_uri":"https://join.artise.co/oauth"}"#,
                        #"{"ios":"","redirect_uri":"https://join.artise.co/oauth"}"#,
                        #"{"ios":"a b","redirect_uri":"https://join.artise.co/oauth"}"#,
                        #"{"ios":"01K7","redirect_uri":"http://join.artise.co/oauth"}"#,
                        #"{"ios":"01K7","redirect_uri":"https://evil.example/oauth"}"#,
                        #"{"ios":"01K7","redirect_uri":"https://join.artise.co/oauth?x=1"}"#,
                        #"{"ios":"01K7"}"#,
                        #""01K7""#]
        for section in sections {
            let file = WorkspaceFile.parse(Data(#"{"co.artise.workspace":{"name":"Acme","oauth":\#(section)}}"#.utf8))
            #expect(file?.branding?.name == "Acme", "\(section)")
            #expect(file?.branding?.oauth == nil, "\(section)")
        }
    }
    
    /// With `oauth` and the server's issuer: the workspace's own client for that issuer, returning to join.artise.co.
    @Test
    func staticClientForTheIssuer() async {
        let transport = FakeTransport([
            "https://mas-k8s.artise.co/.well-known/matrix/client": .init(body: Self.wellKnown),
            "https://matrix.mas-k8s.artise.co/_matrix/client/v1/auth_metadata": .init(body: Self.metadata)
        ])
        let client = WorkspaceClient(transport: transport)
        guard case .ready(let workspace) = await client.resolve(.serverName("mas-k8s.artise.co")) else {
            Issue.record("Expected the workspace")
            return
        }
        let signIn = await client.signInClient(for: workspace)
        #expect(signIn.redirectURL.absoluteString == "https://join.artise.co/oauth")
        #expect(signIn.staticRegistrations == ["https://auth.mas-k8s.artise.co/": "01K7ARTSEAPP1PH0NE00000000"])
    }
    
    /// A server that only has the older metadata endpoint still gives its issuer.
    @Test
    func unstableMetadataEndpoint() async throws {
        let transport = FakeTransport([
            "https://matrix.mas-k8s.artise.co/_matrix/client/v1/auth_metadata": .init(status: 404, body: "{}"),
            "https://matrix.mas-k8s.artise.co/_matrix/client/unstable/org.matrix.msc2965/auth_metadata": .init(body: Self.metadata)
        ])
        let homeserverURL = try #require(URL(string: "https://matrix.mas-k8s.artise.co"))
        let issuer = await WorkspaceClient(transport: transport).issuer(homeserverURL: homeserverURL)
        #expect(issuer == "https://auth.mas-k8s.artise.co/")
    }
    
    /// Without `oauth`, or when the issuer can't be read: dynamic registration and the app's own scheme, as before.
    @Test
    func otherwiseDynamic() async throws {
        let plain = ResolvedWorkspace(slug: "acme", serverName: "acme.artise.co", directoryName: "Acme",
                                      file: WorkspaceFile(homeserverURL: URL(string: "https://matrix.acme.artise.co"), branding: nil))
        let offline = WorkspaceClient(transport: FakeTransport([:]))
        #expect(await offline.signInClient(for: plain) == .dynamic)
        
        let withOAuth = try #require(WorkspaceFile.parse(Data(Self.wellKnown.utf8)))
        let mas = ResolvedWorkspace(slug: "mas-k8s", serverName: "mas-k8s.artise.co", directoryName: nil, file: withOAuth)
        #expect(await offline.signInClient(for: mas) == .dynamic)
        #expect(WorkspaceSignInClient.dynamic.redirectURL.absoluteString == "co.artise.app:/oauth")
        #expect(WorkspaceSignInClient.dynamic.staticRegistrations.isEmpty)
    }
    
    /// Only an https issuer, exactly as written.
    @Test
    func issuerParsing() {
        #expect(AuthMetadata.issuer(from: Data(Self.metadata.utf8)) == "https://auth.mas-k8s.artise.co/")
        #expect(AuthMetadata.issuer(from: Data(#"{"issuer":"http://auth.example/"}"#.utf8)) == nil)
        #expect(AuthMetadata.issuer(from: Data(#"{"issuer":42}"#.utf8)) == nil)
        #expect(AuthMetadata.issuer(from: Data("<html>".utf8)) == nil)
    }
    
    /// A workspace saved before `oauth` existed still loads.
    @Test
    func olderSavedWorkspacesStillDecode() throws {
        let saved = #"{"serverName":"artise.co","file":{"branding":{"name":"Artise","welcome":{}}}}"#
        let workspace = try JSONDecoder().decode(ResolvedWorkspace.self, from: Data(saved.utf8))
        #expect(workspace.branding?.oauth == nil)
    }
}
