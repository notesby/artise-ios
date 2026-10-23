//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

/// Previews for lists and a document's text for search, from the Notes API, kept on the phone.
struct NotesPreviewsTests {
    let room = FakeNotesServer.roomID
    let server = FakeNotesServer()
    let directory = makeTemporaryDirectory()
    
    func makeEngine() -> NotesSyncEngine {
        let tokens = CountingTokenProvider()
        let api = NotesAPIClient(transport: server, tokenSource: OpenIDNotesTokenSource { await tokens.next() })
        return NotesSyncEngine(api: api, directory: directory.appendingPathComponent("store"), cipher: ReversingCipher(),
                               files: NotesFileOptions(directory: directory.appendingPathComponent("files")))
    }
    
    // MARK: - Previews
    
    /// The request names the chat (percent-encoded), the path and the size, and signs in like every other.
    @Test
    func thePreviewRequestIsBuiltRight() async throws {
        server.put("docs/Factura 1.pdf", "%PDF", isNote: false)
        server.setPreview("docs/Factura 1.pdf", png: Data("png-1".utf8), etag: "\"p1\"")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        let preview = try await engine.preview(roomID: room, path: "docs/Factura 1.pdf", size: 128)
        
        let request = try #require(server.requests(to: "preview").first)
        #expect(request.url.absoluteString == "https://chat.artise.co/api/notes/v1/chats/\(FakeNotesServer.encodedRoom)/preview?path=docs%2FFactura%201.pdf&size=128")
        #expect(request.headers["Authorization"] == "Bearer token-1")
        #expect(request.headers["If-None-Match"] == nil)
        guard case .image(let url) = preview else {
            Issue.record("Expected a picture, got \(String(describing: preview))")
            return
        }
        #expect(try Data(contentsOf: url) == Data("png-1".utf8))
    }
    
    /// A picture is fetched once per version and size; the next time it comes from the phone.
    @Test
    func aPictureIsFetchedOnceAndKept() async throws {
        server.put("luna.jpg", "jpg", isNote: false)
        server.setPreview("luna.jpg", png: Data("png-1".utf8), etag: "\"p1\"")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        let first = try await engine.preview(roomID: room, path: "luna.jpg", size: 128)
        let again = try await engine.preview(roomID: room, path: "luna.jpg", size: 128)
        _ = try await engine.preview(roomID: room, path: "luna.jpg", size: 256)
        
        #expect(first == again)
        #expect(server.requests(to: "preview").count == 2)
        #expect(server.requests(to: "preview").last?.query["size"] == "256")
    }
    
    /// A file that changed is asked about with the last picture's ETag; a `304` keeps the picture without new bytes.
    @Test
    func aChangedFileIsAskedWithItsETag() async throws {
        server.put("luna.jpg", "jpg", isNote: false)
        server.setPreview("luna.jpg", png: Data("png-1".utf8), etag: "\"p1\"")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        _ = try await engine.preview(roomID: room, path: "luna.jpg", size: 128)
        
        server.put("luna.jpg", "jpg v2", isNote: false)
        try await engine.sync(roomID: room)
        let preview = try await engine.preview(roomID: room, path: "luna.jpg", size: 128)
        
        let requests = server.requests(to: "preview")
        #expect(requests.count == 2)
        #expect(requests.last?.headers["If-None-Match"] == "\"p1\"")
        guard case .image(let url) = preview else {
            Issue.record("Expected a picture")
            return
        }
        #expect(try Data(contentsOf: url) == Data("png-1".utf8))
        
        // Kept under the new version: no request the next time either.
        _ = try await engine.preview(roomID: room, path: "luna.jpg", size: 128)
        #expect(server.requests(to: "preview").count == 2)
    }
    
    /// A new picture replaces the old one and brings its own ETag.
    @Test
    func aNewPictureReplacesTheOld() async throws {
        server.put("luna.jpg", "jpg", isNote: false)
        server.setPreview("luna.jpg", png: Data("png-1".utf8), etag: "\"p1\"")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        _ = try await engine.preview(roomID: room, path: "luna.jpg", size: 128)
        
        server.put("luna.jpg", "jpg v2", isNote: false)
        server.setPreview("luna.jpg", png: Data("png-2".utf8), etag: "\"p2\"")
        try await engine.sync(roomID: room)
        let preview = try await engine.preview(roomID: room, path: "luna.jpg", size: 128)
        
        guard case .image(let url) = preview else {
            Issue.record("Expected a picture")
            return
        }
        #expect(try Data(contentsOf: url) == Data("png-2".utf8))
        server.put("luna.jpg", "jpg v3", isNote: false)
        try await engine.sync(roomID: room)
        _ = try await engine.preview(roomID: room, path: "luna.jpg", size: 128)
        #expect(server.requests(to: "preview").last?.headers["If-None-Match"] == "\"p2\"")
    }
    
    /// A text file's preview is its first lines.
    @Test
    func textFilesGiveTheirFirstLines() async throws {
        server.put("lista.csv", "pan,2\nleche,1")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        let preview = try await engine.preview(roomID: room, path: "lista.csv", size: 128)
        
        #expect(preview == .text("pan,2\nleche,1"))
        _ = try await engine.preview(roomID: room, path: "lista.csv", size: 128)
        #expect(server.requests(to: "preview").count == 1)
    }
    
    /// Office files and unreadable ones have no preview, and lists don't ask about them again.
    @Test
    func filesWithoutAPreviewAreRemembered() async throws {
        server.put("Contrato.docx", "docx", isNote: false)
        server.put("roto.pdf", "not a pdf", isNote: false)
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        #expect(try await engine.preview(roomID: room, path: "Contrato.docx", size: 128) == nil)
        #expect(try await engine.preview(roomID: room, path: "Contrato.docx", size: 128) == nil)
        #expect(try await engine.preview(roomID: room, path: "roto.pdf", size: 128) == nil)
        #expect(try await engine.preview(roomID: room, path: "roto.pdf", size: 128) == nil)
        #expect(server.requests(to: "preview").count == 2)
    }
    
    /// A file that isn't there fails, and is asked about again next time (it may appear).
    @Test
    func aMissingFileFails() async throws {
        let engine = makeEngine()
        
        await #expect(throws: NotesError.notFound("No such file")) {
            try await engine.preview(roomID: room, path: "nada.pdf", size: 128)
        }
        await #expect(throws: NotesError.self) {
            try await engine.preview(roomID: room, path: "nada.pdf", size: 128)
        }
        #expect(server.requests(to: "preview").count == 2)
    }
    
    // MARK: - Text
    
    /// The pages come with their numbers, and are kept by path and version: a changed file is asked for again.
    @Test
    func documentTextIsKeptByPathAndVersion() async throws {
        server.put("docs/Recetario.pdf", "%PDF", isNote: false)
        server.setText("docs/Recetario.pdf", pages: ["Mole poblano", "chiles y chocolate"])
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        let text = try await engine.documentText(roomID: room, path: "docs/Recetario.pdf")
        let again = try await engine.documentText(roomID: room, path: "docs/Recetario.pdf")
        
        #expect(text.path == "docs/Recetario.pdf")
        #expect(text.version == server.version("docs/Recetario.pdf"))
        #expect(text.pages == [.init(number: 1, text: "Mole poblano"), .init(number: 2, text: "chiles y chocolate")])
        #expect(again == text)
        let request = try #require(server.requests(to: "text").first)
        #expect(request.url.absoluteString == "https://chat.artise.co/api/notes/v1/chats/\(FakeNotesServer.encodedRoom)/text?path=docs%2FRecetario.pdf")
        #expect(server.requests(to: "text").count == 1)
        
        server.put("docs/Recetario.pdf", "%PDF v2", isNote: false)
        server.setText("docs/Recetario.pdf", pages: ["Mole poblano", "chiles y chocolate", "postres"])
        try await engine.sync(roomID: room)
        let changed = try await engine.documentText(roomID: room, path: "docs/Recetario.pdf")
        #expect(changed.pages.count == 3)
        #expect(server.requests(to: "text").count == 2)
    }
    
    /// A note is one page with its text.
    @Test
    func aNoteIsOnePage() async throws {
        server.put("Mole.md", "# Mole\nchiles")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        let text = try await engine.documentText(roomID: room, path: "Mole.md")
        
        #expect(text.pages == [.init(number: 1, text: "# Mole\nchiles")])
    }
    
    /// Too big, no text and not found are each named, so the viewer can say search isn't available.
    @Test
    func textErrorsAreNamed() async throws {
        server.put("grande.pdf", "%PDF", isNote: false)
        server.put("Contrato.docx", "docx", isNote: false)
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        await #expect(throws: NotesError.tooBig("Too big")) {
            try await engine.documentText(roomID: room, path: "grande.pdf")
        }
        await #expect(throws: NotesError.noText("No text for this kind")) {
            try await engine.documentText(roomID: room, path: "Contrato.docx")
        }
        await #expect(throws: NotesError.notFound("No such file")) {
            try await engine.documentText(roomID: room, path: "nada.pdf")
        }
    }
}

/// A Word, Excel or PowerPoint file read in the app through the server's PDF of it, and card previews.
struct NotesOfficePDFTests {
    let room = FakeNotesServer.roomID
    let server = FakeNotesServer()
    let directory = makeTemporaryDirectory()
    
    func makeEngine() -> NotesSyncEngine {
        let tokens = CountingTokenProvider()
        let api = NotesAPIClient(transport: server, tokenSource: OpenIDNotesTokenSource { await tokens.next() })
        return NotesSyncEngine(api: api, directory: directory.appendingPathComponent("store"), cipher: ReversingCipher(),
                               files: NotesFileOptions(directory: directory.appendingPathComponent("files")))
    }
    
    /// The conversion is fetched once per version and kept on the phone.
    @Test
    func theConversionIsFetchedOncePerVersion() async throws {
        server.put("Ventas/Octubre.xlsx", "xlsx", isNote: false)
        server.setPDF("Ventas/Octubre.xlsx", pdf: Data("%PDF-1".utf8))
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        let url = try await engine.officePDF(roomID: room, path: "Ventas/Octubre.xlsx")
        _ = try await engine.officePDF(roomID: room, path: "Ventas/Octubre.xlsx")
        
        #expect(try Data(contentsOf: url) == Data("%PDF-1".utf8))
        let requests = server.requests(to: "pdf")
        #expect(requests.count == 1)
        #expect(requests.first?.url.absoluteString == "https://chat.artise.co/api/notes/v1/chats/\(FakeNotesServer.encodedRoom)/pdf?path=Ventas%2FOctubre.xlsx")
        
        server.put("Ventas/Octubre.xlsx", "xlsx v2", isNote: false)
        server.setPDF("Ventas/Octubre.xlsx", pdf: Data("%PDF-2".utf8))
        try await engine.sync(roomID: room)
        let changed = try await engine.officePDF(roomID: room, path: "Ventas/Octubre.xlsx")
        #expect(try Data(contentsOf: changed) == Data("%PDF-2".utf8))
        #expect(server.requests(to: "pdf").count == 2)
    }
    
    /// No conversion (it failed, or the file isn't an Office file) is its own answer, not a generic error.
    @Test
    func noConversionIsSaidPlainly() async throws {
        server.put("roto.docx", "docx", isNote: false)
        server.put("Mole.md", "# Mole")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        await #expect(throws: NotesError.unreadable("Couldn't convert it")) {
            try await engine.officePDF(roomID: room, path: "roto.docx")
        }
        await #expect(throws: NotesError.noPDF("Not an Office file")) {
            try await engine.officePDF(roomID: room, path: "Mole.md")
        }
    }
    
    /// A card names the version it's about: its preview is kept under that version even before the chat's notes are
    /// on the phone, and a newer version asks again.
    @Test
    func aCardsVersionKeysItsPreview() async throws {
        server.put("Factura.pdf", "%PDF", isNote: false)
        server.setPreview("Factura.pdf", png: Data("png-1".utf8), etag: "\"p1\"")
        let engine = makeEngine()
        
        _ = try await engine.preview(roomID: room, path: "Factura.pdf", size: 512, version: "v1")
        _ = try await engine.preview(roomID: room, path: "Factura.pdf", size: 512, version: "v1")
        #expect(server.requests(to: "preview").count == 1)
        
        server.setPreview("Factura.pdf", png: Data("png-2".utf8), etag: "\"p2\"")
        let newer = try await engine.preview(roomID: room, path: "Factura.pdf", size: 512, version: "v2")
        guard case .image(let url) = newer else {
            Issue.record("Expected a picture")
            return
        }
        #expect(try Data(contentsOf: url) == Data("png-2".utf8))
        #expect(server.requests(to: "preview").count == 2)
    }
}
