//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A chat that has notes, as the Notes API lists it.
public struct NotesChat: Equatable, Sendable, Codable {
    public let roomID: String
    public let name: String
    /// Changes whenever anything in the chat's notes changes.
    public let tree: String
    
    public init(roomID: String, name: String, tree: String) {
        self.roomID = roomID
        self.name = name
        self.tree = tree
    }
}

/// One file in a chat's notes, as the server lists it.
public struct NotesFile: Equatable, Sendable, Codable {
    public let path: String
    /// The file's git blob hash. It's sent back as the base version when saving.
    public let version: String
    public let size: Int64
    /// Seconds since the epoch.
    public let modified: Int64
    /// Text opened with the note endpoints. Anything else (photos, PDFs…) is a raw file.
    public let isNote: Bool
    
    public init(path: String, version: String, size: Int64, modified: Int64, isNote: Bool) {
        self.path = path
        self.version = version
        self.size = size
        self.modified = modified
        self.isNote = isNote
    }
}

/// A chat's file list.
public struct NotesTree: Equatable, Sendable {
    public let tree: String
    public let files: [NotesFile]
    /// Every folder on the server, empty ones included ("Recetas", "Recetas/Postres").
    public let folders: [String]
    
    public init(tree: String, files: [NotesFile], folders: [String] = []) {
        self.tree = tree
        self.files = files
        self.folders = folders
    }
}

public struct Note: Equatable, Sendable {
    public let path: String
    public let version: String
    public let content: String
    
    public init(path: String, version: String, content: String) {
        self.path = path
        self.version = version
        self.content = content
    }
}

/// What's on the server now, sent with a conflict or "exists" answer.
public struct ServerCopy: Equatable, Sendable, Codable {
    public let path: String
    public let version: String
    /// The text, for notes.
    public let content: String?
    
    public init(path: String, version: String, content: String?) {
        self.path = path
        self.version = version
        self.content = content
    }
}

public struct SavedNote: Equatable, Sendable {
    public let path: String
    public let version: String
    /// The server merged this edit with someone else's: `content` is the note now.
    public let merged: Bool
    public let content: String?
    
    public init(path: String, version: String, merged: Bool, content: String?) {
        self.path = path
        self.version = version
        self.merged = merged
        self.content = content
    }
}

public struct MovedNote: Equatable, Sendable {
    public let from: String
    public let to: String
    public let version: String
    /// Notes whose links the server rewrote to follow the move.
    public let linksUpdated: [String]
    
    public init(from: String, to: String, version: String, linksUpdated: [String]) {
        self.from = from
        self.to = to
        self.version = version
        self.linksUpdated = linksUpdated
    }
}

public struct MovedFolder: Equatable, Sendable {
    public let from: String
    public let to: String
    public let moved: [MovedNote]
    public let linksUpdated: [String]
    
    public init(from: String, to: String, moved: [MovedNote], linksUpdated: [String]) {
        self.from = from
        self.to = to
        self.moved = moved
        self.linksUpdated = linksUpdated
    }
}

public struct DeletedFolder: Equatable, Sendable {
    public let path: String
    public let notes: Int
    public let files: Int
    
    public init(path: String, notes: Int, files: Int) {
        self.path = path
        self.notes = notes
        self.files = files
    }
}

public struct NotesSearchResult: Equatable, Sendable {
    public let path: String
    public let lines: [String]
    
    public init(path: String, lines: [String]) {
        self.path = path
        self.lines = lines
    }
}

public struct NoteLinks: Equatable, Sendable {
    public struct Outgoing: Equatable, Sendable {
        public let target: String
        /// `nil` when the linked note doesn't exist yet, or when several notes answer to the name (see `candidates`).
        public let path: String?
        /// The notes sharing the link's name, when there's more than one: the person chooses, never the first.
        public let candidates: [String]
        
        public init(target: String, path: String?, candidates: [String] = []) {
            self.target = target
            self.path = path
            self.candidates = candidates
        }
    }
    
    public struct Backlink: Equatable, Sendable {
        public let path: String
        public let line: String
        
        public init(path: String, line: String) {
            self.path = path
            self.line = line
        }
    }
    
    public let path: String
    public let outgoing: [Outgoing]
    public let backlinks: [Backlink]
    
    public init(path: String, outgoing: [Outgoing], backlinks: [Backlink]) {
        self.path = path
        self.outgoing = outgoing
        self.backlinks = backlinks
    }
}

/// A person, place or thing with a note of its own, as the Notes API lists it: the notes in the folders the chat's
/// `SCHEMA.md` marks `(pages)`, with the header Obsidian reads, plus every photo and document as a page of its kind.
public struct NotesPage: Equatable, Sendable, Codable, Identifiable {
    public let path: String
    /// The note's name, or the file's name for a photo or document.
    public let title: String
    /// "person", "place", "thing", "client", "image", "document"… as the chat's `SCHEMA.md` names them.
    public let type: String
    /// The folder the page is in, "" at the top level.
    public let folder: String
    /// Other names people use for it, from the note's `aliases` header: `[[Mamá]]` finds Ana.
    public let aliases: [String]
    public let summary: String
    /// A note, as opposed to a photo or document.
    public let isNote: Bool
    
    public var id: String {
        path
    }
    
    public init(path: String, title: String, type: String, folder: String, aliases: [String], summary: String, isNote: Bool) {
        self.path = path
        self.title = title
        self.type = type
        self.folder = folder
        self.aliases = aliases
        self.summary = summary
        self.isNote = isNote
    }
}

public struct NotesGraph: Equatable, Sendable {
    public struct Edge: Equatable, Sendable {
        public let from: String
        public let to: String
        
        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }
    
    public let nodes: [String]
    public let edges: [Edge]
    
    public init(nodes: [String], edges: [Edge]) {
        self.nodes = nodes
        self.edges = edges
    }
}

/// Who made a change, as the server describes it.
public struct ChangeAuthor: Equatable, Sendable {
    /// The person's display name; `nil` for Ari on its own and synced devices.
    public let who: String?
    /// ari, automation, routine, brief, ari_own, reaction, chat, app, files or sync; `nil` from older servers.
    public let how: String?
    /// Which automation or routine, e.g. "#3"; empty when there's none.
    public let detail: String
    /// The plain name older servers send, used when `how` is unknown.
    public let by: String
    
    public init(who: String?, how: String?, detail: String, by: String) {
        self.who = who
        self.how = how
        self.detail = detail
        self.by = by
    }
}

public struct NoteVersion: Equatable, Sendable {
    public let commit: String
    /// ISO 8601 with the server's offset, e.g. "2026-09-29T18:02:11-06:00".
    public let at: String
    public let message: String
    public let author: ChangeAuthor
    
    public init(commit: String, at: String, message: String, author: ChangeAuthor) {
        self.commit = commit
        self.at = at
        self.message = message
        self.author = author
    }
}

// MARK: - The phone's copy

/// A file as the phone has it.
public struct LocalFile: Equatable, Sendable {
    public let path: String
    /// The server version this copy is based on; empty for a note created offline and not sent yet.
    public let version: String
    public let size: Int64
    public let modified: Int64
    public let isNote: Bool
    /// The text for notes; `nil` for raw files and for notes not downloaded yet.
    public let content: String?
    /// An edit to this file is waiting to be sent or for the person to choose.
    public let hasLocalEdits: Bool
    
    public init(path: String, version: String, size: Int64, modified: Int64, isNote: Bool, content: String?, hasLocalEdits: Bool) {
        self.path = path
        self.version = version
        self.size = size
        self.modified = modified
        self.isNote = isNote
        self.content = content
        self.hasLocalEdits = hasLocalEdits
    }
}

public enum EditKind: String, Sendable, Codable {
    case save
    case delete
    /// A photo or file added on this phone, waiting to be uploaded.
    case upload
}

public enum EditState: String, Sendable, Codable {
    /// Waiting to be sent.
    case pending
    /// Someone changed the same lines meanwhile: show both, let the person choose or combine.
    case conflict
    /// Someone deleted the note meanwhile: keep this copy, or drop it.
    case deleted
    /// A note with this name appeared meanwhile: keep both under different names.
    case exists
    /// The server refused it for good (too big, not allowed); `error` says why.
    case rejected
}

/// An edit made on this phone that hasn't reached the server yet.
public struct PendingEdit: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let path: String
    public let kind: EditKind
    public let state: EditState
    /// The text this phone wants to save, for `.save`.
    public let content: String?
    /// The server's copy, for `.conflict` and `.exists`.
    public let serverCopy: ServerCopy?
    public let error: String?
    
    public init(id: Int64, path: String, kind: EditKind, state: EditState, content: String?, serverCopy: ServerCopy?, error: String?) {
        self.id = id
        self.path = path
        self.kind = kind
        self.state = state
        self.content = content
        self.serverCopy = serverCopy
        self.error = error
    }
}

/// What a sync did.
/// What a sync in progress is doing.
public struct SyncActivity: Equatable, Sendable {
    /// Notes still to download in this sync; 0 when nothing is coming down.
    public var downloadingNotes: Int
    
    public init(downloadingNotes: Int = 0) {
        self.downloadingNotes = downloadingNotes
    }
}

public struct SyncReport: Equatable, Sendable {
    /// Edits the server accepted.
    public var sent: Int
    /// Edits now waiting for the person to choose.
    public var needChoice: Int
    /// Files downloaded or updated from the server.
    public var updated: Int
    /// Files removed because they're gone from the server.
    public var removed: Int
    /// Edits the server couldn't take this time; they stay queued for the next sync.
    public var failed: Int
    
    public init(sent: Int = 0, needChoice: Int = 0, updated: Int = 0, removed: Int = 0, failed: Int = 0) {
        self.sent = sent
        self.needChoice = needChoice
        self.updated = updated
        self.removed = removed
        self.failed = failed
    }
    
    public var changedAnything: Bool {
        self != SyncReport()
    }
}
