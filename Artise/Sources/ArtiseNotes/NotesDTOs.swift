//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// The Notes API's JSON (docs/notes-api.md in family-wiki).
// Request bodies encode every field, nil included: the server needs `base_version: null`
// to create a note, and Swift's synthesized `Encodable` would leave a nil out.

struct ChatsDTO: Decodable {
    struct Chat: Decodable {
        let id: String
        let name: String
        let tree: String
    }
    
    let chats: [Chat]
}

struct TreeDTO: Decodable {
    struct File: Decodable {
        let path: String
        let version: String
        let size: Int64
        let modified: Int64
        let note: Bool
    }
    
    let tree: String
    let files: [File]
    let folders: [String]?
}

struct NoteDTO: Decodable {
    let path: String
    let version: String
    let content: String
}

struct SaveNoteDTO: Encodable {
    let path: String
    let content: String
    let baseVersion: String?
    
    enum CodingKeys: String, CodingKey {
        case path, content
        case baseVersion = "base_version"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(content, forKey: .content)
        try container.encode(baseVersion, forKey: .baseVersion)
    }
}

struct SavedDTO: Decodable {
    let path: String
    let version: String
    let merged: Bool?
    let content: String?
}

struct MoveDTO: Encodable {
    let from: String
    let to: String
    let baseVersion: String
    
    enum CodingKeys: String, CodingKey {
        case from, to
        case baseVersion = "base_version"
    }
}

struct MoveFolderDTO: Encodable {
    let from: String
    let to: String
    let folder = true
}

struct MovedDTO: Decodable {
    let from: String
    let to: String
    let version: String
    let linksUpdated: [String]?
    
    enum CodingKeys: String, CodingKey {
        case from, to, version
        case linksUpdated = "links_updated"
    }
}

struct MovedFolderDTO: Decodable {
    struct Moved: Decodable {
        let from: String
        let to: String
        let version: String
    }
    
    let from: String
    let to: String
    let moved: [Moved]
    let linksUpdated: [String]?
    
    enum CodingKeys: String, CodingKey {
        case from, to, moved
        case linksUpdated = "links_updated"
    }
}

struct FolderDTO: Encodable {
    let path: String
}

struct DeletedFolderDTO: Decodable {
    let path: String
    let notes: Int?
    let files: Int?
}

struct SearchDTO: Decodable {
    struct Result: Decodable {
        let path: String
        let lines: [String]
    }
    
    let results: [Result]
}

struct LinksDTO: Decodable {
    struct Outgoing: Decodable {
        let target: String
        let path: String?
        let candidates: [String]?
    }
    
    struct Backlink: Decodable {
        let path: String
        let line: String
    }
    
    let path: String
    let outgoing: [Outgoing]
    let backlinks: [Backlink]
}

struct PagesDTO: Decodable {
    struct Page: Decodable {
        let path: String
        let title: String
        let type: String?
        let folder: String?
        let aliases: [String]?
        let summary: String?
        let note: Bool?
    }
    
    let pages: [Page]
}

struct GraphDTO: Decodable {
    let nodes: [String]
    let edges: [[String]]
}

struct HistoryDTO: Decodable {
    struct Version: Decodable {
        let commit: String
        let at: String
        let message: String
        let by: String
        let who: String?
        let how: String?
        let detail: String?
    }
    
    let versions: [Version]
}

struct ChangesDTO: Decodable {
    struct Change: Decodable {
        struct File: Decodable {
            let path: String
            let change: String
            let from: String?
        }
        
        let commit: String
        let at: String
        let message: String
        let by: String
        let who: String?
        let how: String?
        let detail: String?
        let files: [File]
    }
    
    let changes: [Change]
    let more: Bool?
}

struct ErrorDTO: Decodable {
    struct Current: Decodable {
        let path: String
        let version: String
        let content: String?
    }
    
    let error: String?
    let message: String?
    let current: Current?
    let usedBy: [String]?
    let files: Int?
    let folders: Int?
    
    enum CodingKeys: String, CodingKey {
        case error, message, current, files, folders
        case usedBy = "used_by"
    }
}
