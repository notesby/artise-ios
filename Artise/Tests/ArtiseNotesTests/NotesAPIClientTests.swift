//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

struct NotesAPIClientTests {
    let server = FakeNotesServer()
    let tokens = CountingTokenProvider()
    let client: NotesAPIClient
    
    init() {
        let tokens = tokens
        client = NotesAPIClient(transport: server, tokenSource: OpenIDNotesTokenSource { await tokens.next() })
    }
    
    /// The contract wants room IDs fully percent-encoded in the path: `!abc:artise.co` → `%21abc%3Aartise.co`.
    @Test
    func roomIDIsPercentEncodedInThePath() async throws {
        _ = try await client.tree(roomID: FakeNotesServer.roomID, etag: nil)
        
        let request = try #require(server.requests.first)
        #expect(request.url.absoluteString == "https://chat.artise.co/api/notes/v1/chats/\(FakeNotesServer.encodedRoom)/tree")
    }
    
    /// Query values with spaces, accents and `+` reach the server unchanged.
    @Test
    func pathsInTheQueryKeepEveryCharacter() async throws {
        server.put("Recetas/Mole + arroz ñ.md", "# Mole")
        
        let note = try await client.note(roomID: FakeNotesServer.roomID, path: "Recetas/Mole + arroz ñ.md")
        
        #expect(note.content == "# Mole")
        #expect(server.requests.last?.url.absoluteString.contains("Recetas%2FMole%20%2B%20arroz%20%C3%B1.md") == true)
    }
    
    /// Creating a note must send `"base_version": null`: a field left out is a different request for the server.
    @Test
    func creatingANoteSendsANullBaseVersion() async throws {
        _ = try await client.saveNote(roomID: FakeNotesServer.roomID, path: "Súper.md", content: "- leche", baseVersion: nil)
        
        let body = try #require(server.requests(to: "note", method: "PUT").first?.body)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains(#""base_version":null"#))
        #expect(server.content("Súper.md") == "- leche")
    }
    
    /// Every request signs in with the OpenID token, never anything else.
    @Test
    func requestsCarryTheOpenIDToken() async throws {
        _ = try await client.chats()
        
        #expect(server.requests.first?.headers["Authorization"] == "Bearer token-1")
    }
    
    /// A `401` asks for a fresh token and retries once.
    @Test
    func anExpiredTokenIsReplacedAndTheRequestRetried() async throws {
        server.setValidTokens(["token-2"])
        
        let chats = try await client.chats()
        
        #expect(chats.map(\.name) == ["Familia"])
        #expect(await tokens.issued == 2)
        #expect(server.requests.map { $0.headers["Authorization"] } == ["Bearer token-1", "Bearer token-2"])
    }
    
    /// When the fresh token is refused too, the person has to sign in again.
    @Test
    func aSecondRefusalIsUnauthorized() async {
        server.setValidTokens([])
        
        await #expect(throws: NotesError.unauthorized("Sign in again")) {
            try await client.chats()
        }
        #expect(server.requests.count == 2)
    }
    
    /// The tree's ETag goes back as `If-None-Match`, and an unchanged tree answers `304`.
    @Test
    func anUnchangedTreeIsNotModified() async throws {
        server.put("Súper.md", "- leche")
        guard case let .changed(tree, etag) = try await client.tree(roomID: FakeNotesServer.roomID, etag: nil) else {
            Issue.record("Expected the tree")
            return
        }
        #expect(tree.files.map(\.path) == ["Súper.md"])
        
        let second = try await client.tree(roomID: FakeNotesServer.roomID, etag: etag)
        
        #expect(second == .notModified)
        #expect(server.requests.last?.headers["If-None-Match"] == etag)
    }
    
    /// A conflict carries the server's copy, so the person can compare both.
    @Test
    func aConflictCarriesTheServersCopy() async throws {
        let first = server.put("Súper.md", "- leche")
        server.put("Súper.md", "- pan")
        
        await #expect(throws: try NotesError.conflict("Same lines edited", current: ServerCopy(path: "Súper.md", version: #require(server.version("Súper.md")), content: "- pan"))) {
            try await client.saveNote(roomID: FakeNotesServer.roomID, path: "Súper.md", content: "- huevos", baseVersion: first)
        }
    }
    
    /// Error codes map to their cases, and unknown errors keep their status.
    @Test
    func errorCodesMapToCases() {
        func error(_ status: Int, _ json: String) -> NotesError {
            NotesAPIClient.error(status: status, body: Data(json.utf8))
        }
        
        #expect(error(409, #"{"error": "not_empty", "message": "m", "files": 2, "folders": 1}"#) == .notEmpty("m", files: 2, folders: 1))
        #expect(error(409, #"{"error": "in_use", "message": "m", "used_by": ["a.md"]}"#) == .inUse("m", usedBy: ["a.md"]))
        #expect(error(413, #"{"error": "too_big", "message": "m"}"#) == .tooBig("m"))
        #expect(error(502, "Bad gateway") == .server(status: 502, message: "HTTP 502"))
        #expect(error(401, "") == .unauthorized("HTTP 401"))
    }
    
    /// No connection is a network error, which the sync treats as "try later".
    @Test
    func offlineIsANetworkError() async {
        server.setOffline(true)
        
        await #expect {
            try await client.chats()
        } throws: { error in
            if case .network = error as? NotesError {
                true
            } else {
                false
            }
        }
    }
}

struct OpenIDNotesTokenSourceTests {
    /// A token is reused until a minute before it expires, then a new one is requested.
    @Test
    func tokensAreReusedUntilShortlyBeforeTheyExpire() async throws {
        let clock = TestClock()
        let tokens = CountingTokenProvider()
        let source = OpenIDNotesTokenSource(now: { clock.now }) { await tokens.next() }
        
        #expect(try await source.token() == "token-1")
        clock.advance(by: 3600 - 61)
        #expect(try await source.token() == "token-1")
        clock.advance(by: 2)
        #expect(try await source.token() == "token-2")
    }
    
    /// Only the refused token is forgotten: a newer one from another request stays.
    @Test
    func invalidateOnlyDropsTheRefusedToken() async throws {
        let tokens = CountingTokenProvider()
        let source = OpenIDNotesTokenSource { await tokens.next() }
        let first = try await source.token()
        
        await source.invalidate("some-older-token")
        #expect(try await source.token() == first)
        
        await source.invalidate(first)
        #expect(try await source.token() == "token-2")
    }
}
