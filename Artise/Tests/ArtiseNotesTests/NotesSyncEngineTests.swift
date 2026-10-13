//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

struct NotesSyncEngineTests {
    let room = FakeNotesServer.roomID
    let server = FakeNotesServer()
    let directory = makeTemporaryDirectory()
    
    func makeEngine() -> NotesSyncEngine {
        let tokens = CountingTokenProvider()
        server.setValidTokens(["token-1", "token-2", "token-3"])
        let api = NotesAPIClient(transport: server, tokenSource: OpenIDNotesTokenSource { await tokens.next() })
        return NotesSyncEngine(api: api, directory: directory, cipher: ReversingCipher())
    }
    
    // MARK: - Pulling
    
    /// The first sync downloads every note's text, and lists photos without downloading them.
    @Test
    func firstSyncDownloadsNotesAndListsFiles() async throws {
        server.put("Súper.md", "- leche")
        server.put("attachments/foto.jpg", "jpeg bytes", isNote: false)
        server.setFolders(["Recetas", "attachments"])
        let engine = makeEngine()
        
        let report = try await engine.sync(roomID: room)
        
        #expect(report.updated == 2)
        #expect(try await engine.file(roomID: room, path: "Súper.md")?.content == "- leche")
        #expect(try await engine.file(roomID: room, path: "attachments/foto.jpg")?.content == nil)
        #expect(server.requests(to: "raw").isEmpty)
        #expect(try await engine.folders(roomID: room) == ["attachments", "Recetas"])
    }
    
    /// Nothing changed: the sync costs one `304` and downloads nothing.
    @Test
    func anUnchangedChatCostsOneNotModified() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        let before = server.requests.count
        
        let report = try await engine.sync(roomID: room)
        
        #expect(report == SyncReport())
        #expect(server.requests.count == before + 1)
        #expect(server.requests.last?.path.hasSuffix("/tree") == true)
    }
    
    /// Notes changed or removed on the server are updated or dropped on the phone.
    @Test
    func changesOnTheServerReachThePhone() async throws {
        server.put("Súper.md", "- leche")
        server.put("Viejo.md", "adiós")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        server.put("Súper.md", "- leche\n- pan")
        server.remove("Viejo.md")
        let report = try await engine.sync(roomID: room)
        
        #expect(report.updated == 1)
        #expect(report.removed == 1)
        #expect(try await engine.file(roomID: room, path: "Súper.md")?.content == "- leche\n- pan")
        #expect(try await engine.file(roomID: room, path: "Viejo.md") == nil)
    }
    
    /// A live tree hash equal to ours means there's nothing to do, so nothing is sent.
    @Test
    func aKnownTreeSkipsTheSync() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        let before = server.requests.count
        
        #expect(try await engine.onTreeChanged(roomID: room, tree: server.tree) == nil)
        #expect(server.requests.count == before)
        
        server.put("Súper.md", "- pan")
        #expect(try await engine.onTreeChanged(roomID: room, tree: server.tree)?.updated == 1)
    }
    
    // MARK: - Pushing
    
    /// An edit made offline is kept on the phone, and sent with the version it started from once online.
    @Test
    func offlineEditsAreSentLater() async throws {
        let base = server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        server.setOffline(true)
        
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- leche\n- pan")
        await #expect(throws: NotesError.self) { try await engine.sync(roomID: room) }
        
        #expect(try await engine.file(roomID: room, path: "Súper.md")?.content == "- leche\n- pan")
        #expect(try await engine.file(roomID: room, path: "Súper.md")?.hasLocalEdits == true)
        
        server.setOffline(false)
        let report = try await engine.sync(roomID: room)
        
        #expect(report.sent == 1)
        #expect(server.content("Súper.md") == "- leche\n- pan")
        #expect(server.requests(to: "note", method: "PUT").last?.json?["base_version"] as? String == base)
        #expect(try await engine.edits(roomID: room).isEmpty)
    }
    
    /// Several edits before a sync go out as one save, still based on the first version.
    @Test
    func editsBeforeASyncAreCoalesced() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- leche\n- pan")
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- leche\n- pan\n- huevos")
        try await engine.sync(roomID: room)
        
        #expect(server.requests(to: "note", method: "PUT").count == 1)
        #expect(server.content("Súper.md") == "- leche\n- pan\n- huevos")
    }
    
    /// A note created on the phone is sent with `base_version: null`.
    @Test
    func newNotesAreCreatedOnTheServer() async throws {
        let engine = makeEngine()
        
        try await engine.createNote(roomID: room, path: "Ideas.md", content: "# Ideas")
        try await engine.sync(roomID: room)
        
        let body = try #require(server.requests(to: "note", method: "PUT").first?.json)
        #expect(body.keys.contains("base_version"))
        #expect(body["base_version"] is NSNull)
        #expect(server.content("Ideas.md") == "# Ideas")
        #expect(try await engine.file(roomID: room, path: "Ideas.md")?.version == server.version("Ideas.md"))
    }
    
    /// Creating a note the phone already has fails right away.
    @Test
    func creatingATakenNameFails() async throws {
        server.put("Ideas.md", "# Ideas")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        await #expect(throws: NotesError.self) {
            try await engine.createNote(roomID: room, path: "Ideas.md", content: "otra")
        }
    }
    
    /// The server merged edits to different lines: the merged text becomes the note on the phone.
    @Test
    func aMergedSaveShowsTheMergedText() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        server.put("Súper.md", "- leche\n- pan")
        server.setMerge { server, mine in server + "\n" + mine.split(separator: "\n").last.map(String.init)! }
        
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- leche\n- huevos")
        try await engine.sync(roomID: room)
        
        #expect(try await engine.file(roomID: room, path: "Súper.md")?.content == "- leche\n- pan\n- huevos")
    }
    
    /// Someone edited the same lines: the edit waits for a choice, and later edits to that note wait behind it,
    /// while other notes still go out.
    @Test
    func aConflictWaitsForAChoiceWithoutBlockingOtherNotes() async throws {
        server.put("Súper.md", "- leche")
        server.put("Ideas.md", "# Ideas")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        server.put("Súper.md", "- pan")
        
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- huevos")
        try await engine.editNote(roomID: room, path: "Ideas.md", content: "# Ideas\n- viaje")
        let report = try await engine.sync(roomID: room)
        
        #expect(report.sent == 1)
        #expect(report.needChoice == 1)
        #expect(server.content("Ideas.md") == "# Ideas\n- viaje")
        let edit = try #require(try await engine.edits(roomID: room).first)
        #expect(edit.state == .conflict)
        #expect(edit.serverCopy?.content == "- pan")
        // The phone keeps the person's text and never takes the server's over it.
        #expect(try await engine.file(roomID: room, path: "Súper.md")?.content == "- huevos")
    }
    
    /// The person combined both versions: it's saved over the server's version.
    @Test
    func aResolvedConflictIsSavedOverTheServersVersion() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        server.put("Súper.md", "- pan")
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- huevos")
        try await engine.sync(roomID: room)
        let edit = try #require(try await engine.edits(roomID: room).first)
        
        try await engine.resolveConflict(roomID: room, editID: edit.id, content: "- pan\n- huevos")
        try await engine.sync(roomID: room)
        
        #expect(server.content("Súper.md") == "- pan\n- huevos")
        #expect(try await engine.edits(roomID: room).isEmpty)
    }
    
    /// Discarding an edit goes back to the server's copy.
    @Test
    func discardingAConflictShowsTheServersCopy() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        server.put("Súper.md", "- pan")
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- huevos")
        try await engine.sync(roomID: room)
        let edit = try #require(try await engine.edits(roomID: room).first)
        
        try await engine.discardEdit(roomID: room, editID: edit.id)
        
        #expect(try await engine.file(roomID: room, path: "Súper.md")?.content == "- pan")
        #expect(try await engine.edits(roomID: room).isEmpty)
    }
    
    /// The note was deleted meanwhile: keeping it saves the phone's copy as a new note.
    @Test
    func aNoteDeletedMeanwhileCanBeKept() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        server.remove("Súper.md")
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- pan")
        try await engine.sync(roomID: room)
        let edit = try #require(try await engine.edits(roomID: room).first)
        #expect(edit.state == .deleted)
        
        try await engine.keepDeletedNote(roomID: room, editID: edit.id)
        try await engine.sync(roomID: room)
        
        #expect(server.content("Súper.md") == "- pan")
    }
    
    /// The name was taken meanwhile: both notes are kept, the phone's under the new name.
    @Test
    func aTakenNameKeepsBothNotes() async throws {
        let engine = makeEngine()
        try await engine.createNote(roomID: room, path: "Ideas.md", content: "mías")
        server.put("Ideas.md", "de Luis")
        try await engine.sync(roomID: room)
        let edit = try #require(try await engine.edits(roomID: room).first)
        #expect(edit.state == .exists)
        
        try await engine.saveUnderNewName(roomID: room, editID: edit.id, newPath: "Ideas (2).md")
        try await engine.sync(roomID: room)
        
        #expect(server.content("Ideas.md") == "de Luis")
        #expect(server.content("Ideas (2).md") == "mías")
        #expect(try await engine.file(roomID: room, path: "Ideas.md")?.content == "de Luis")
    }
    
    /// An error on the server's side keeps that edit for later and goes on with the others.
    @Test
    func aServerErrorKeepsTheEditForTheNextSync() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- pan")
        server.failNext("note", status: 502, error: "bad_gateway")
        
        let first = try await engine.sync(roomID: room)
        #expect(first.failed == 1)
        #expect(try await engine.edits(roomID: room).first?.state == .pending)
        
        let second = try await engine.sync(roomID: room)
        #expect(second.sent == 1)
        #expect(server.content("Súper.md") == "- pan")
    }
    
    /// A refusal for good (too big) waits for the person instead of being retried forever.
    @Test
    func aRefusedEditIsSetAside() async throws {
        server.put("Súper.md", "- leche")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        try await engine.editNote(roomID: room, path: "Súper.md", content: "- pan")
        server.failNext("note", status: 413, error: "too_big")
        
        let report = try await engine.sync(roomID: room)
        
        #expect(report.needChoice == 1)
        #expect(try await engine.edits(roomID: room).first?.state == .rejected)
    }
    
    /// Deleting queues the deletion; once sent, the note is gone on both sides.
    @Test
    func deletionsReachTheServer() async throws {
        server.put("Viejo.md", "adiós")
        let engine = makeEngine()
        try await engine.sync(roomID: room)
        
        try await engine.deleteFile(roomID: room, path: "Viejo.md")
        #expect(try await engine.file(roomID: room, path: "Viejo.md") == nil)
        try await engine.sync(roomID: room)
        
        #expect(server.content("Viejo.md") == nil)
        #expect(try await engine.edits(roomID: room).isEmpty)
    }
    
    /// Deleting a note that never reached the server sends nothing.
    @Test
    func deletingAnUnsentNoteSendsNothing() async throws {
        let engine = makeEngine()
        try await engine.createNote(roomID: room, path: "Borrador.md", content: "x")
        
        try await engine.deleteFile(roomID: room, path: "Borrador.md")
        try await engine.sync(roomID: room)
        
        #expect(server.requests(to: "note", method: "PUT").isEmpty)
        #expect(server.requests(to: "file", method: "DELETE").isEmpty)
    }
    
    // MARK: - Chats and flags
    
    /// Chats no longer listed by the server are forgotten, with their notes.
    @Test
    func refreshingChatsForgetsChatsThatAreGone() async throws {
        let engine = makeEngine()
        try await engine.createNote(roomID: "!gone:artise.co", path: "a.md", content: "x")
        
        let chats = try await engine.refreshChats()
        
        #expect(chats.map(\.roomID) == [room])
        #expect(try await engine.cachedChats().map(\.name) == ["Familia"])
        #expect(try await engine.files(roomID: "!gone:artise.co").isEmpty)
    }
    
    /// The privacy notice shows once per account, and stays seen after a restart.
    @Test
    func thePrivacyNoticeIsRemembered() async throws {
        #expect(try await makeEngine().hasSeenPrivacyNotice() == false)
        try await makeEngine().markPrivacyNoticeSeen()
        #expect(try await makeEngine().hasSeenPrivacyNotice() == true)
    }
    
    /// Open screens hear about local edits.
    @Test
    func editsNotifyOpenScreens() async throws {
        let engine = makeEngine()
        let changes = await engine.changes(roomID: room)
        var iterator = changes.makeAsyncIterator()
        
        try await engine.createNote(roomID: room, path: "a.md", content: "x")
        
        #expect(await iterator.next() != nil)
    }
    
    /// Folders come from the server's list and from the files' paths.
    @Test
    func foldersIncludeParentsOfFiles() {
        #expect(NotesSyncEngine.parentFolders(of: "a/b/c.md") == ["a", "a/b"])
        #expect(NotesSyncEngine.parentFolders(of: "c.md").isEmpty)
    }
}
