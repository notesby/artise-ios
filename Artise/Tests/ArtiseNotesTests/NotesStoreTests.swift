//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Testing

struct NotesStoreTests {
    let directory = makeTemporaryDirectory()
    
    /// What's written comes back after the app restarts (a new store over the same folder).
    @Test
    func recordsSurviveARestart() async throws {
        let store = NotesStore(directory: directory, cipher: ReversingCipher())
        try await store.updateIndex { $0.flags.insert("privacy_notice_seen") }
        try await store.updateChat("!abc:artise.co") { record in
            record.files["Súper.md"] = FileRecord(path: "Súper.md", version: "v1", size: 7, modified: 1, isNote: true, content: "- leche")
        }
        
        let reopened = NotesStore(directory: directory, cipher: ReversingCipher())
        
        #expect(try await reopened.index().flags == ["privacy_notice_seen"])
        #expect(try await reopened.chat("!abc:artise.co")?.files["Súper.md"]?.content == "- leche")
    }
    
    /// Notes never reach the disk as plain text.
    @Test
    func filesOnDiskAreEncrypted() async throws {
        let store = NotesStore(directory: directory, cipher: ReversingCipher())
        try await store.updateChat("!abc:artise.co") { record in
            record.files["Diario.md"] = FileRecord(path: "Diario.md", version: "v1", size: 6, modified: 1, isNote: true, content: "secreto")
        }
        
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        let written = files.filter { $0.pathExtension == "notes" }
        #expect(!written.isEmpty)
        for file in written {
            let text = try String(decoding: Data(contentsOf: file), as: UTF8.self)
            #expect(!text.contains("secreto"))
            #expect(!text.contains("Diario"))
        }
    }
    
    /// A change that throws leaves the record as it was, in memory and on disk.
    @Test
    func aFailedChangeWritesNothing() async throws {
        struct Failure: Error { }
        let store = NotesStore(directory: directory, cipher: ReversingCipher())
        try await store.updateChat("!abc:artise.co") { $0.name = "Familia" }
        
        await #expect(throws: Failure.self) {
            try await store.updateChat("!abc:artise.co") { record in
                record.name = "Otro"
                throw Failure()
            }
        }
        
        #expect(try await store.chat("!abc:artise.co")?.name == "Familia")
        #expect(try await NotesStore(directory: directory, cipher: ReversingCipher()).chat("!abc:artise.co")?.name == "Familia")
    }
    
    /// Signing out removes every chat and the index.
    @Test
    func removeAllForgetsEverything() async throws {
        let store = NotesStore(directory: directory, cipher: ReversingCipher())
        try await store.updateChat("!abc:artise.co") { $0.name = "Familia" }
        
        try await store.removeAll()
        
        #expect(try await store.chat("!abc:artise.co") == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
    
    /// A file from a newer app version isn't misread: the store refuses it instead.
    @Test
    func aNewerFormatIsRefused() throws {
        let newer = Data(#"{"format": 99, "record": {}}"#.utf8)
        
        #expect(throws: NotesStoreError.unsupportedFormat(99)) {
            try NotesStoreFormat.decode(IndexRecord.self, from: newer)
        }
    }
    
    /// Migration test for format 1, the first format: a record written by this version reads back the same.
    /// Each new format adds a test here that reads a record written in the previous one.
    @Test
    func formatOneReadsBack() throws {
        let version1 = Data(#"""
        {"format": 1, "record": {"roomID": "!abc:artise.co", "name": "Familia", "tree": "t1", "etag": "\"t1\"",
         "files": {"Súper.md": {"path": "Súper.md", "version": "v1", "size": 7, "modified": 1, "isNote": true, "content": "- leche"}},
         "edits": [{"id": 1, "kind": "save", "path": "Súper.md", "content": "- pan", "baseVersion": "v1", "state": "pending", "createdAt": 5}],
         "folders": ["Recetas"], "nextEditID": 2}}
        """#.utf8)
        
        let record = try NotesStoreFormat.decode(ChatRecord.self, from: version1)
        
        #expect(record.files["Súper.md"]?.content == "- leche")
        #expect(record.edits.first?.state == .pending)
        #expect(record.edits.first?.baseVersion == "v1")
        #expect(record.folders == ["Recetas"])
        #expect(record.nextEditID == 2)
    }
    
    #if canImport(CryptoKit)
    /// The real cipher: what it seals opens with the same key, and not with another one.
    @Test
    func aesGCMOpensOnlyWithTheSameKey() throws {
        let cipher = AESGCMNotesCipher(keyData: Data(repeating: 1, count: 32))
        let sealed = try cipher.seal(Data("receta".utf8))
        
        #expect(try cipher.open(sealed) == Data("receta".utf8))
        #expect(throws: (any Error).self) {
            try AESGCMNotesCipher(keyData: Data(repeating: 2, count: 32)).open(sealed)
        }
    }
    #endif
}
