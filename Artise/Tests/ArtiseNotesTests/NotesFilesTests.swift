//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Synchronization
import Testing

struct NotesFilesTests {
    let room = FakeNotesServer.roomID
    let server = FakeNotesServer()
    let directory = makeTemporaryDirectory()
    let prefetch = Flag()
    
    func makeEngine(cacheLimit: Int64 = NotesFileOptions.maxCacheBytes,
                    convert: @escaping @Sendable (Data, String) -> Data? = { _, _ in nil }) -> NotesSyncEngine {
        let tokens = CountingTokenProvider()
        server.setValidTokens(["token-1", "token-2", "token-3"])
        let api = NotesAPIClient(transport: server, tokenSource: OpenIDNotesTokenSource { await tokens.next() })
        let prefetch = prefetch
        let options = NotesFileOptions(cacheDirectory: directory.appendingPathComponent("cache"),
                                       pendingDirectory: directory.appendingPathComponent("pending"),
                                       convertPhoto: convert,
                                       canPrefetch: { prefetch.isOn },
                                       cacheLimit: cacheLimit)
        return NotesSyncEngine(api: api, directory: directory.appendingPathComponent("store"), cipher: ReversingCipher(), files: options)
    }
    
    // MARK: - Uploads
    
    /// Text edits go first, then what others changed comes down, and photos upload last: a big photo doesn't hold
    /// back the rest. A note that shows a photo still waits for that photo.
    @Test
    func uploadsGoAfterThePull() async throws {
        server.put("Otra.md", "de alguien")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        server.put("Nueva.md", "de otra persona")
        try await engine.createNote(roomID: room, path: "Lista.md", content: "- pan")
        let path = try await engine.addAttachment(roomID: room, fileName: "luna.png", data: Data("png".utf8), contentType: "image/png")
        try await engine.createNote(roomID: room, path: "Hoy.md", content: "![[luna.png]]")
        let before = server.requests.count
        
        try await engine.sync(roomID: room)
        
        let order = server.requests.dropFirst(before).compactMap { request -> String? in
            if request.method == "PUT" {
                return request.path.hasSuffix("/raw") ? "photo" : request.json?["path"] as? String
            }
            return request.path.hasSuffix("/tree") ? "tree" : nil
        }
        let tree = try #require(order.firstIndex(of: "tree"))
        let photo = try #require(order.firstIndex(of: "photo"))
        let note = try #require(order.firstIndex(of: "Hoy.md"))
        #expect(order.first == "Lista.md")
        #expect(tree < photo)
        #expect(photo < note)
        #expect(path == "attachments/luna.png")
        #expect(try await engine.file(roomID: room, path: "Nueva.md")?.content == "de otra persona")
    }
    
    /// A photo added offline shows at once from the phone, and goes up before the note that embeds it.
    @Test
    func attachmentsUploadBeforeTheNotesThatShowThem() async throws {
        let engine = makeEngine()
        server.setOffline(true)
        
        let path = try await engine.addAttachment(roomID: room, fileName: "luna.png", data: Data("png".utf8), contentType: "image/png")
        try await engine.createNote(roomID: room, path: "Hoy.md", content: "![[luna.png]]")
        #expect(path == "attachments/luna.png")
        #expect(try await engine.uploads(roomID: room) == [path: .waiting])
        let local = try await engine.attachment(roomID: room, path: path)
        #expect(try String(contentsOf: local, encoding: .utf8) == "png")
        
        server.setOffline(false)
        try await engine.sync(roomID: room)
        
        let puts = server.requests.filter { $0.method == "PUT" }.map { $0.path.split(separator: "/").last.map(String.init) ?? "" }
        #expect(puts == ["raw", "note"])
        #expect(server.content(path) == "png")
        #expect(try await engine.uploads(roomID: room).isEmpty)
    }
    
    /// A name taken meanwhile on the server: the upload takes the next free name, and the note follows it.
    @Test
    func aTakenNameIsRenamedAndTheNoteFollows() async throws {
        let engine = makeEngine()
        try await engine.addAttachment(roomID: room, fileName: "luna.png", data: Data("mía".utf8), contentType: "image/png")
        try await engine.createNote(roomID: room, path: "Hoy.md", content: "![[luna.png]]")
        server.put("attachments/luna.png", "de Luis", isNote: false)
        
        try await engine.sync(roomID: room)
        
        #expect(server.content("attachments/luna (2).png") == "mía")
        #expect(server.content("attachments/luna.png") == "de Luis")
        #expect(server.content("Hoy.md") == "![[luna (2).png]]")
    }
    
    /// A HEIC photo is turned into a JPEG before it uploads, and the note is changed to the new name.
    @Test
    func photosAreConvertedBeforeUploading() async throws {
        let engine = makeEngine { _, type in type == "image/heic" ? Data("jpeg".utf8) : nil }
        try await engine.addAttachment(roomID: room, fileName: "IMG_1.heic", data: Data("heic".utf8), contentType: "image/heic")
        try await engine.createNote(roomID: room, path: "Hoy.md", content: "![[IMG_1.heic]]")
        
        try await engine.sync(roomID: room)
        
        #expect(server.content("attachments/IMG_1.jpg") == "jpeg")
        #expect(server.content("attachments/IMG_1.heic") == nil)
        #expect(server.content("Hoy.md") == "![[IMG_1.jpg]]")
    }
    
    /// Cancelling an upload drops the file and takes it out of the notes.
    @Test
    func cancellingAnUploadTakesItOutOfNotes() async throws {
        let engine = makeEngine()
        let path = try await engine.addAttachment(roomID: room, fileName: "luna.png", data: Data("png".utf8), contentType: "image/png")
        try await engine.createNote(roomID: room, path: "Hoy.md", content: "Hoy\n\n![[luna.png]]")
        
        try await engine.cancelUpload(roomID: room, path: path)
        
        #expect(try await engine.file(roomID: room, path: path) == nil)
        #expect(try await engine.file(roomID: room, path: "Hoy.md")?.content == "Hoy")
        #expect(try await engine.uploads(roomID: room).isEmpty)
    }
    
    // MARK: - Downloads
    
    /// A photo downloads once and comes from the phone after that.
    @Test
    func downloadsAreKept() async throws {
        server.put("attachments/luna.png", "png", isNote: false)
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        _ = try await engine.attachment(roomID: room, path: "attachments/luna.png")
        _ = try await engine.attachment(roomID: room, path: "attachments/luna.png")
        
        #expect(server.requests(to: "raw", method: "GET").count == 1)
        #expect(try await engine.cachedAttachment(roomID: room, path: "attachments/luna.png") != nil)
    }
    
    /// The phone keeps its copies under the limit, dropping the least recently used.
    @Test
    func theCacheStaysUnderItsLimit() async throws {
        server.put("a.pdf", String(repeating: "a", count: 600), isNote: false)
        server.put("b.pdf", String(repeating: "b", count: 600), isNote: false)
        let engine = makeEngine(cacheLimit: 1000)
        try await engine.sync(roomID: room)
        
        _ = try await engine.attachment(roomID: room, path: "a.pdf")
        try await Task.sleep(for: .milliseconds(20))
        _ = try await engine.attachment(roomID: room, path: "b.pdf")
        
        #expect(try await engine.cachedAttachment(roomID: room, path: "a.pdf") == nil)
        #expect(try await engine.cachedAttachment(roomID: room, path: "b.pdf") != nil)
    }
    
    /// With several workspaces, one limit counts all their copies: another workspace's older file goes first.
    @Test
    func theCacheLimitCountsEveryWorkspace() async throws {
        let root = directory.appendingPathComponent("caches")
        let other = root.appendingPathComponent("other-workspace")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let otherFile = other.appendingPathComponent("old.pdf")
        try Data(repeating: 1, count: 600).write(to: otherFile)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: otherFile.path)
        
        server.put("a.pdf", String(repeating: "a", count: 600), isNote: false)
        let tokens = CountingTokenProvider()
        server.setValidTokens(["token-1", "token-2"])
        let api = NotesAPIClient(transport: server, tokenSource: OpenIDNotesTokenSource { await tokens.next() })
        let options = NotesFileOptions(cacheDirectory: root.appendingPathComponent("this-workspace"),
                                       pendingDirectory: directory.appendingPathComponent("pending"),
                                       cacheLimit: 1000,
                                       sharedCacheRoot: root)
        let engine = NotesSyncEngine(api: api, directory: directory.appendingPathComponent("store"), cipher: ReversingCipher(), files: options)
        try await engine.sync(roomID: room)
        _ = try await engine.attachment(roomID: room, path: "a.pdf")
        
        #expect(!FileManager.default.fileExists(atPath: otherFile.path))
        #expect(try await engine.cachedAttachment(roomID: room, path: "a.pdf") != nil)
    }
    
    /// On Wi-Fi, embedded photos download after a sync; documents and big photos wait to be opened.
    @Test
    func photosPrefetchOnlyWhenAllowed() async throws {
        server.put("attachments/luna.png", "png", isNote: false)
        server.put("factura.pdf", "pdf", isNote: false)
        server.put("Hoy.md", "![[luna.png]] ![[factura.pdf]]")
        let engine = makeEngine()
        
        try await engine.sync(roomID: room)
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests(to: "raw").isEmpty)
        
        prefetch.isOn = true
        server.put("Hoy.md", "![[luna.png]] ![[factura.pdf]] hoy")
        try await engine.sync(roomID: room)
        try await Task.sleep(for: .milliseconds(200))
        
        #expect(server.requests(to: "raw").map { $0.query["path"] } == ["attachments/luna.png"])
    }
    
    // MARK: - Deleting and moving
    
    /// A photo notes use isn't deleted by mistake: the person is told which notes use it first.
    @Test
    func mediaInUseIsNotDeletedByMistake() async throws {
        server.put("attachments/luna.png", "png", isNote: false)
        server.put("Hoy.md", "Hoy\n\n![[luna.png]]")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        await #expect(throws: NotesError.inUse("Used by 1 notes", usedBy: ["Hoy.md"])) {
            try await engine.deleteMedia(roomID: room, path: "attachments/luna.png", removeFromNotes: false)
        }
        
        try await engine.deleteMedia(roomID: room, path: "attachments/luna.png", removeFromNotes: true)
        try await engine.sync(roomID: room)
        #expect(server.content("Hoy.md") == "Hoy")
        #expect(server.content("attachments/luna.png") == nil)
    }
    
    /// The media list says which notes use each file.
    @Test
    func mediaListsWhoUsesEachFile() async throws {
        server.put("attachments/luna.png", "png", isNote: false)
        server.put("attachments/sol.png", "png", isNote: false)
        server.put("Hoy.md", "![[luna.png]]")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        let media = try await engine.media(roomID: room)
        
        #expect(media.map(\.path) == ["attachments/luna.png", "attachments/sol.png"])
        #expect(media.map(\.usedBy) == [["Hoy.md"], []])
    }
    
    /// Renaming moves the note on the server and on the phone.
    @Test
    func renamingANote() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        try await engine.moveFile(roomID: room, from: "Súper.md", to: "Listas/Súper.md")
        
        #expect(server.content("Listas/Súper.md") == "- leche")
        #expect(try await engine.file(roomID: room, path: "Listas/Súper.md")?.content == "- leche")
        #expect(try await engine.file(roomID: room, path: "Súper.md") == nil)
    }
    
    /// A note with unsent changes can't be renamed yet.
    @Test
    func unsentChangesBlockARename() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- pan")
        
        await #expect(throws: NotesError.self) {
            try await engine.moveFile(roomID: room, from: "Súper.md", to: "Otra.md")
        }
    }
    
    /// Folders: created (with parents), renamed with everything inside, deleted after a confirmation when not empty.
    @Test
    func folders() async throws {
        server.put("Recetas/Mole.md", "# Mole")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        try await engine.createFolder(roomID: room, path: "Viajes/2026")
        #expect(try await engine.folders(roomID: room) == ["Recetas", "Viajes", "Viajes/2026"])
        
        try await engine.moveFolder(roomID: room, from: "Recetas", to: "Cocina")
        #expect(try await engine.file(roomID: room, path: "Cocina/Mole.md")?.content == "# Mole")
        
        await #expect(throws: NotesError.notEmpty("Not empty", files: 1, folders: 0)) {
            try await engine.deleteFolder(roomID: room, path: "Cocina", recursive: false)
        }
        try await engine.deleteFolder(roomID: room, path: "Cocina", recursive: true)
        #expect(try await engine.file(roomID: room, path: "Cocina/Mole.md") == nil)
    }
    
    /// Names: "attachments/foto (2).jpg" when taken, hidden names cleaned, photos renamed to .jpg.
    @Test
    func attachmentNames() {
        #expect(NotesSyncEngine.freeAttachmentPath("foto.jpg", taken: []) == "attachments/foto.jpg")
        #expect(NotesSyncEngine.freeAttachmentPath("foto.jpg", taken: ["attachments/foto.jpg"]) == "attachments/foto (2).jpg")
        #expect(NotesSyncEngine.freeAttachmentPath(".oculto", taken: []) == "attachments/oculto")
        #expect(NotesSyncEngine.jpegName("IMG_1.HEIC") == "IMG_1.jpg")
        #expect(NotesSyncEngine.mimeType(of: "a.heic") == "image/heic")
        #expect(NotesSyncEngine.stableHash("a") == NotesSyncEngine.stableHash("a"))
        #expect(NotesSyncEngine.stableHash("a") != NotesSyncEngine.stableHash("b"))
    }
}

/// A switch a test flips, read from any thread.
final class Flag: Sendable {
    private let value = Mutex(false)
    
    var isOn: Bool {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}
