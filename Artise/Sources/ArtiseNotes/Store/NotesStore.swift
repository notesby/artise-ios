//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The phone's encrypted copy of an account's notes.
///
/// Each chat is one sealed file and the chat list is another, so an edit rewrites only its chat.
/// Records stay in memory once read. Every change is written to disk before it returns, atomically,
/// so a crash leaves either the old or the new version.
actor NotesStore {
    private let directory: URL
    private let cipher: NotesCipher
    private var cachedIndex: IndexRecord?
    private var cachedChats: [String: ChatRecord] = [:]
    
    init(directory: URL, cipher: NotesCipher) {
        self.directory = directory
        self.cipher = cipher
    }
    
    // MARK: - Index
    
    func index() throws -> IndexRecord {
        if let cachedIndex {
            return cachedIndex
        }
        let index = try load(IndexRecord.self, from: indexURL) ?? IndexRecord()
        cachedIndex = index
        return index
    }
    
    @discardableResult
    func updateIndex<T>(_ change: (inout IndexRecord) throws -> T) throws -> T {
        var index = try index()
        let result = try change(&index)
        try save(index, to: indexURL)
        cachedIndex = index
        return result
    }
    
    // MARK: - Chats
    
    /// The chat's record, or `nil` when the phone has nothing for it.
    func chat(_ roomID: String) throws -> ChatRecord? {
        if let cached = cachedChats[roomID] {
            return cached
        }
        let record = try load(ChatRecord.self, from: chatURL(roomID))
        cachedChats[roomID] = record
        return record
    }
    
    /// Changes the chat's record, creating it when the phone has nothing for it yet.
    /// When `change` throws, nothing is written.
    @discardableResult
    func updateChat<T>(_ roomID: String, _ change: (inout ChatRecord) throws -> T) throws -> T {
        var record = try chat(roomID) ?? ChatRecord(roomID: roomID, name: index().chats.first { $0.roomID == roomID }?.name ?? "")
        let before = record
        let result = try change(&record)
        if record != before {
            try save(record, to: chatURL(roomID))
            cachedChats[roomID] = record
        }
        return result
    }
    
    /// Every chat the phone holds notes for.
    func storedRoomIDs() -> [String] {
        let folder = directory.appendingPathComponent("chats")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name in
            guard name.hasSuffix(".notes") else { return nil }
            var base64 = String(name.dropLast(".notes".count))
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            return Data(base64Encoded: base64).map { String(decoding: $0, as: UTF8.self) }
        }
    }
    
    func removeChat(_ roomID: String) throws {
        cachedChats[roomID] = nil
        let url = chatURL(roomID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    /// Forgets everything; used when the account signs out.
    func removeAll() throws {
        cachedIndex = nil
        cachedChats = [:]
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
    
    // MARK: - Files on disk
    
    private var indexURL: URL {
        directory.appendingPathComponent("index.notes")
    }
    
    /// Room IDs hold `!` and `:`, so the file name is the ID in URL-safe base64.
    private func chatURL(_ roomID: String) -> URL {
        let name = Data(roomID.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return directory.appendingPathComponent("chats").appendingPathComponent(name + ".notes")
    }
    
    private func load<Record: Codable>(_ type: Record.Type, from url: URL) throws -> Record? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let sealed = try Data(contentsOf: url)
        return try NotesStoreFormat.decode(type, from: cipher.open(sealed))
    }
    
    private func save(_ record: some Codable, to url: URL) throws {
        try prepare(url.deletingLastPathComponent())
        let sealed = try cipher.seal(NotesStoreFormat.encode(record))
        #if os(iOS)
        try sealed.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try sealed.write(to: url, options: .atomic)
        #endif
    }
    
    private func prepare(_ folder: URL) throws {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS) || os(macOS)
        // A cache of the server: it comes back with a sync, so it stays out of backups.
        var store = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? store.setResourceValues(values)
        #endif
    }
}
