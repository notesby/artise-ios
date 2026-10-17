//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseWorkspaces
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

struct WorkspaceClientTests {
    static let artise = #"{"slug":"artise","name":"Artise","server_name":"artise.co","homeserver_url":"https://matrix.artise.co","status":"active"}"#
    static let wellKnown = #"{"m.homeserver":{"base_url":"https://matrix.artise.co"},"co.artise.workspace":{"version":1,"name":"Artise Team"}}"#
    
    /// 200 and active: the workspace, with its file. `server_name` is used as given, not built from the slug.
    @Test
    func activeWorkspace() async {
        let transport = FakeTransport([
            "https://api.artise.co/v1/workspaces/artise": .init(body: Self.artise),
            "https://artise.co/.well-known/matrix/client": .init(body: Self.wellKnown)
        ])
        let result = await WorkspaceClient(transport: transport).resolve(.slug("artise"))
        guard case .ready(let workspace) = result else {
            Issue.record("Expected a workspace, got \(result)")
            return
        }
        #expect(workspace.serverName == "artise.co")
        #expect(workspace.slug == "artise")
        #expect(workspace.displayName == "Artise Team")
        #expect(workspace.file?.homeserverURL?.absoluteString == "https://matrix.artise.co")
    }
    
    /// Suspended: no sign-in, with the workspace's name for the message.
    @Test
    func suspendedWorkspace() async {
        let body = Self.artise.replacingOccurrences(of: "active", with: "suspended")
        let client = WorkspaceClient(transport: FakeTransport(["https://api.artise.co/v1/workspaces/artise": .init(body: body)]))
        #expect(await client.resolve(.slug("artise")) == .paused(name: "Artise"))
    }
    
    /// A status the app doesn't know never opens sign-in.
    @Test
    func unknownStatusIsPaused() {
        let body = Data(Self.artise.replacingOccurrences(of: "active", with: "archived").utf8)
        guard case .suspended = WorkspaceDirectory.result(statusCode: 200, retryAfter: nil, body: body) else {
            Issue.record("An unknown status must not count as active")
            return
        }
    }
    
    /// 404: "No workspace called …".
    @Test
    func unknownWorkspace() async {
        let client = WorkspaceClient(transport: FakeTransport(["https://api.artise.co/v1/workspaces/nonexistent-ws":
                .init(status: 404, body: #"{"errcode":"NOT_FOUND"}"#)]))
        #expect(await client.resolve(.slug("nonexistent-ws")) == .notFound(slug: "nonexistent-ws"))
    }
    
    /// 429: too many tries, with the server's wait.
    @Test
    func rateLimited() async {
        let client = WorkspaceClient(transport: FakeTransport(["https://api.artise.co/v1/workspaces/acme":
                .init(status: 429, headers: ["Retry-After": "42"], body: "{}")]))
        #expect(await client.lookup(slug: "acme") == .rateLimited(retryAfter: 42))
        #expect(await client.resolve(.slug("acme")) == .rateLimited)
    }
    
    /// No network, a server error or an unreadable answer: a retryable error, never another server.
    @Test
    func unreachable() async {
        #expect(await WorkspaceClient(transport: FakeTransport([:])).resolve(.slug("acme")) == .unreachable)
        let broken = FakeTransport(["https://api.artise.co/v1/workspaces/acme": .init(status: 502, body: "Bad gateway")])
        #expect(await WorkspaceClient(transport: broken).resolve(.slug("acme")) == .unreachable)
        let garbled = FakeTransport(["https://api.artise.co/v1/workspaces/acme": .init(body: "<html>")])
        #expect(await WorkspaceClient(transport: garbled).resolve(.slug("acme")) == .unreachable)
    }
    
    /// A server name skips the directory. Without a readable file it still signs in, with Artise's look.
    @Test
    func serverNameWithoutFile() async {
        let transport = FakeTransport([:])
        let result = await WorkspaceClient(transport: transport).resolve(.serverName("artise.co"))
        #expect(result == .ready(ResolvedWorkspace(slug: nil, serverName: "artise.co", directoryName: nil, file: nil)))
        #expect(transport.requested == ["https://artise.co/.well-known/matrix/client"])
    }
    
    /// Answers are kept for the server's `max-age`, then asked again.
    @Test
    func answersAreCachedForMaxAge() async {
        let clock = Clock()
        let transport = FakeTransport([
            "https://api.artise.co/v1/workspaces/artise": .init(headers: ["Cache-Control": "public, max-age=300"], body: Self.artise),
            "https://artise.co/.well-known/matrix/client": .init(headers: ["Cache-Control": "max-age=300"], body: Self.wellKnown)
        ])
        let client = WorkspaceClient(transport: transport, now: { clock.now })
        _ = await client.resolve(.slug("artise"))
        _ = await client.resolve(.slug("artise"))
        #expect(transport.requested.count == 2)
        clock.now += 301
        _ = await client.resolve(.slug("artise"))
        #expect(transport.requested.count == 4)
    }
    
    /// Only `max-age` keeps an answer; `no-store` and `no-cache` don't.
    @Test
    func cacheControl() {
        #expect(CacheControl.maxAge("max-age=300") == 300)
        #expect(CacheControl.maxAge("public, MAX-AGE=60") == 60)
        #expect(CacheControl.maxAge("no-store, max-age=300") == nil)
        #expect(CacheControl.maxAge("no-cache") == nil)
        #expect(CacheControl.maxAge(nil) == nil)
        #expect(CacheControl.maxAge("max-age=soon") == nil)
    }
}

/// Answers by URL; anything else fails as if offline.
extension WorkspaceClientTests {
    /// The QR sign-in shows only where the server says it supports it (mas-k8s today, not artise.co).
    @Test
    func qrSignInSupport() async throws {
        let url = try #require(URL(string: "https://matrix.mas-k8s.artise.co"))
        let versions = "https://matrix.mas-k8s.artise.co/_matrix/client/versions"
        let on = FakeTransport([versions: .init(body: #"{"versions":["v1.11"],"unstable_features":{"org.matrix.msc4108":true}}"#)])
        #expect(await WorkspaceClient(transport: on).supportsQRSignIn(homeserverURL: url))
        let off = FakeTransport([versions: .init(body: #"{"versions":["v1.11"],"unstable_features":{"org.matrix.msc4108":false}}"#)])
        #expect(await !WorkspaceClient(transport: off).supportsQRSignIn(homeserverURL: url))
        #expect(await !WorkspaceClient(transport: FakeTransport([versions: .init(body: #"{"versions":[]}"#)])).supportsQRSignIn(homeserverURL: url))
        #expect(await !WorkspaceClient(transport: FakeTransport([:])).supportsQRSignIn(homeserverURL: url))
    }
}

final class FakeTransport: WorkspaceHTTPTransport, @unchecked Sendable {
    struct Answer {
        var status = 200
        var headers: [String: String] = [:]
        var body: String
    }
    
    private let answers: [String: Answer]
    private let lock = NSLock()
    private var log: [URLRequest] = []
    
    init(_ answers: [String: Answer]) {
        self.answers = answers
    }
    
    var requested: [String] {
        lock.withLock { log.compactMap { $0.url?.absoluteString } }
    }
    
    var requests: [URLRequest] {
        lock.withLock { log }
    }
    
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { log.append(request) }
        guard let url = request.url, let answer = answers[url.absoluteString],
              let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers) else {
            throw URLError(.notConnectedToInternet)
        }
        return (Data(answer.body.utf8), response)
    }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_790_000_000)
    
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
