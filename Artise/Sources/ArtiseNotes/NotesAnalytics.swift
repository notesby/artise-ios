//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

/// How notes are used, for people who said yes on "Help improve Artise": only what was done and the kind of file,
/// never a note's name, a chat's name or any text. The same events as the Android app.
public enum NotesAnalyticsScreen: String, Sendable {
    case notesChats = "NotesChats"
    case notesFolder = "NotesFolder"
    case note = "Note"
    case noteEditor = "NoteEditor"
    case notesSearch = "NotesSearch"
    case notesMap = "NotesMap"
    case notesChoices = "NotesChoices"
    case notesMedia = "NotesMedia"
    case notesHistory = "NotesHistory"
    case noteHistory = "NoteHistory"
    case noteVersion = "NoteVersion"
}

public enum NotesAnalyticsAction: String, Sendable {
    case noteCreated = "NoteCreated"
    case noteSaved = "NoteSaved"
    case noteDeleted = "NoteDeleted"
    case noteRenamed = "NoteRenamed"
    case attachmentAdded = "AttachmentAdded"
    case uploadRetried = "UploadRetried"
    case uploadCancelled = "UploadCancelled"
    case choiceMade = "ChoiceMade"
    case searchUsed = "SearchUsed"
    case mediaDeleted = "MediaDeleted"
}

/// One notes action; `kind` says "photo" or "document" for attachments, or which choice was made.
public struct NotesAnalyticsEvent: Equatable, Sendable {
    public let action: NotesAnalyticsAction
    public let kind: String?
    
    public init(_ action: NotesAnalyticsAction, kind: String? = nil) {
        self.action = action
        self.kind = kind
    }
    
    /// "NotesNoteSaved", as the Android app names it.
    public var name: String {
        "Notes" + action.rawValue
    }
    
    public var properties: [String: String] {
        kind.map { ["kind": $0] } ?? [:]
    }
}
