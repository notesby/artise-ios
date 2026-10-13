//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum NotesStoreError: Error, Equatable {
    case cannotEncrypt
    case cannotCreateKey
    case cannotReadKey(Int32)
    /// Written by a newer version of the app.
    case unsupportedFormat(Int)
    case unreadable(String)
}

// What the store keeps, as written to disk (encrypted). Any change here needs a new
// `NotesStoreFormat.current`, a migration in `NotesStoreFormat.migrate` and a migration test.

/// One chat's notes on the phone: the files as last seen on the server (or as edited here), and the
/// queue of edits made on this phone.
struct ChatRecord: Codable, Equatable {
    var roomID: String
    var name: String
    /// The tree hash and ETag of the last pull; `nil` before the first one.
    var tree: String?
    var etag: String?
    var files: [String: FileRecord]
    /// Edits waiting to reach the server, sent in `id` order.
    var edits: [EditRecord]
    /// Every folder on the server, empty ones included (folders holding files also come from the files' paths).
    var folders: [String]
    /// The id the next queued edit gets.
    var nextEditID: Int64
    
    init(roomID: String, name: String) {
        self.roomID = roomID
        self.name = name
        files = [:]
        edits = []
        folders = []
        nextEditID = 1
    }
}

/// One file as last seen on the server, or as edited here when an edit is queued.
struct FileRecord: Codable, Equatable {
    var path: String
    /// Empty for a file created on this phone and not sent yet.
    var version: String
    var size: Int64
    var modified: Int64
    var isNote: Bool
    /// Only kept for notes; photos and files are fetched on demand.
    var content: String?
}

struct EditRecord: Codable, Equatable {
    var id: Int64
    var kind: EditKind
    var path: String
    /// The text to save; for uploads, the name of the file waiting on the phone.
    var content: String?
    /// The version the edit started from; `nil` creates the file.
    var baseVersion: String?
    var state: EditState
    /// The server's copy sent with a conflict or exists answer.
    var serverVersion: String?
    var serverContent: String?
    var error: String?
    /// Milliseconds since the epoch.
    var createdAt: Int64
    /// For uploads, the file's type.
    var contentType: String?
}

/// Account-wide things: the chats with notes and one-time flags.
struct IndexRecord: Codable, Equatable {
    var chats: [NotesChat]
    var flags: Set<String>
    
    init() {
        chats = []
        flags = []
    }
}

/// The store's on-disk format: a version number around each record, so older files can be migrated.
enum NotesStoreFormat {
    static let current = 1
    
    struct Envelope<Record: Codable>: Codable {
        let format: Int
        let record: Record
    }
    
    static func encode(_ record: some Codable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(Envelope(format: current, record: record))
    }
    
    static func decode<Record: Codable>(_ type: Record.Type, from data: Data) throws -> Record {
        let migrated = try migrate(data)
        return try JSONDecoder().decode(Envelope<Record>.self, from: migrated).record
    }
    
    /// Brings a record written by an older app up to `current`, one version at a time.
    static func migrate(_ data: Data) throws -> Data {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = object["format"] as? Int else {
            throw NotesStoreError.unreadable("No format version")
        }
        guard format <= current else {
            throw NotesStoreError.unsupportedFormat(format)
        }
        // Version 1 is the first format: nothing to migrate yet. A future `case 1:` rewrites `object` to version 2.
        return data
    }
}
