//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A chat's notes for the screens: the phone's copy first (it works offline), kept in sync with the Notes API.
public protocol NotesRepository: Sendable {
    /// Whether this account has seen the one-time "Ari can read notes" notice.
    func hasSeenPrivacyNotice() async throws -> Bool
    func markPrivacyNoticeSeen() async throws
    
    /// Chats with notes, as last synced.
    func cachedChats() async throws -> [NotesChat]
    /// Asks the server which chats have notes, and forgets chats no longer listed.
    func refreshChats() async throws -> [NotesChat]
    
    func files(roomID: String) async throws -> [LocalFile]
    func file(roomID: String, path: String) async throws -> LocalFile?
    /// Every folder in the chat's notes, empty ones included, parents before children.
    func folders(roomID: String) async throws -> [String]
    /// Unsent edits, including those waiting for the person to choose.
    func edits(roomID: String) async throws -> [PendingEdit]
    /// The chat's pages (people, places, things, photos and documents), as last fetched with the tree; empty before.
    func pages(roomID: String) async throws -> [NotesPage]
    
    /// Yields whenever the phone's copy of the chat's notes changes.
    func changes(roomID: String) async -> AsyncStream<Void>
    
    /// Sends queued edits in order, then pulls what changed. An unchanged chat costs one `304`.
    @discardableResult
    func sync(roomID: String) async throws -> SyncReport
    /// Syncs the chats this phone already holds notes for, a few at a time; returns how many synced.
    @discardableResult
    func syncKnownChats(concurrency: Int) async -> Int
    /// The chats this phone already holds notes for.
    func knownRoomIDs() async -> [String]
    /// What a sync in progress is doing, for the folder's progress line.
    func activity(roomID: String) async -> SyncActivity
    /// A live `co.artise.notes` state event said the chat's tree is now `tree`: syncs only if that differs from ours.
    @discardableResult
    func onTreeChanged(roomID: String, tree: String) async throws -> SyncReport?
    
    /// Saves the text on the phone and queues it. Several edits before a sync go out as one.
    func editNote(roomID: String, path: String, content: String) async throws
    /// Creates a note on the phone and queues it. Fails with `.exists` if the phone already has one there.
    func createNote(roomID: String, path: String, content: String) async throws
    /// Removes the file from the phone and queues its deletion.
    func deleteFile(roomID: String, path: String) async throws
    
    /// For a conflict: saves `content` (the person's choice or combination) over the server's version.
    func resolveConflict(roomID: String, editID: Int64, content: String) async throws
    /// For a note deleted meanwhile: saves this phone's copy again as a new note.
    func keepDeletedNote(roomID: String, editID: Int64) async throws
    /// For a name taken meanwhile: saves this phone's note under `newPath`, keeping both.
    func saveUnderNewName(roomID: String, editID: Int64, newPath: String) async throws
    /// Drops the edit and goes back to the server's copy.
    func discardEdit(roomID: String, editID: Int64) async throws
    
    /// Starts a sync that goes on if the screen that asked for it closes. Failures are silent: the queue stays.
    func syncInBackground(roomID: String)
    
    // MARK: - Photos and files
    
    /// Adds a photo or file to `attachments/`; it shows at once and uploads with the next sync. Returns its path.
    func addAttachment(roomID: String, fileName: String, data: Data, contentType: String) async throws -> String
    /// The photo or file on the phone, downloaded once and kept while it doesn't change.
    func attachment(roomID: String, path: String) async throws -> URL
    /// The photo or file's copy on the phone, if it's there already; never downloads.
    func cachedAttachment(roomID: String, path: String) async throws -> URL?
    /// Photos and files added on this phone and not on the server yet, by path.
    func uploads(roomID: String) async throws -> [String: UploadStatus]
    /// Every photo and file, with the notes that use each one.
    func media(roomID: String) async throws -> [MediaFile]
    /// A small picture of a PDF's first page or a photo (or a text file's first lines) for lists, kept on the phone
    /// per file version: one request each, none for a file the server said has no preview (`nil`).
    func preview(roomID: String, path: String, size: Int) async throws -> NotePreview?
    /// The same, for a version named elsewhere (a document card in the chat) rather than the phone's listing.
    func preview(roomID: String, path: String, size: Int, version: String?) async throws -> NotePreview?
    /// The server's PDF of an Office file, kept on the phone per file version. `.noPDF` (or `.unreadable`) when there
    /// isn't one: the viewer then says to use "Open with".
    func officePDF(roomID: String, path: String) async throws -> URL
    /// A document's text page by page, for search; kept by path and version while the app runs (needs a connection).
    func documentText(roomID: String, path: String) async throws -> NotesDocumentText
    
    // MARK: - Charts and dashboards (need a connection, except a picture already on the phone)
    
    /// The picture of a chart or dashboard last drawn at this size and mode, if the phone has one; never asks.
    func cachedDrawing(roomID: String, path: String, size: Int, mode: NoteDrawingMode) async -> URL?
    /// A chart's or dashboard's picture as drawn now, asked for every time with the last one's ETag (a chart that
    /// reads records changes while its file doesn't). `nil` when it can't be drawn.
    func drawing(roomID: String, path: String, size: Int, mode: NoteDrawingMode) async throws -> URL?
    /// A chart as data (title, caption, as of) and SVG.
    func chart(roomID: String, path: String, mode: NoteDrawingMode) async throws -> NotesChart
    /// A dashboard as a web page.
    func dashboard(roomID: String, path: String) async throws -> String
    /// A chart's PNG or PDF, a note's or dashboard's PDF, made now for the share sheet, as a named file on the phone.
    func export(roomID: String, path: String, format: NoteExportFormat) async throws -> URL
    /// The record types a chart's `source` may read in this chat.
    func recordTypes(roomID: String) async throws -> [NotesRecordType]
    /// An unsaved chart's picture (at most 512 px); `.badChart` with the server's sentence when it can't be drawn.
    func chartPreview(roomID: String, content: String, size: Int, mode: NoteDrawingMode) async throws -> Data
    
    func retryUpload(roomID: String, path: String) async throws
    /// Drops an upload not sent yet, and takes it out of the notes that embed it.
    func cancelUpload(roomID: String, path: String) async throws
    /// Deletes a photo or file; fails with `.inUse` when notes use it, unless `removeFromNotes`.
    func deleteMedia(roomID: String, path: String, removeFromNotes: Bool) async throws
    
    // MARK: - History (needs a connection)
    
    /// A note's last 50 versions, newest first.
    func history(roomID: String, path: String) async throws -> [NoteVersion]
    /// The chat's latest changes, newest first; with `before` (the last commit of a page), the next older page.
    func changeHistory(roomID: String, before: String?) async throws -> NotesChangesPage
    /// A note as it was at a commit from `history`. To restore it, save its text as a normal edit.
    func noteAt(roomID: String, path: String, commit: String) async throws -> Note
    
    // MARK: - Files and folders (need a connection)
    
    /// Renames or moves a note, photo or file; the server updates the links to it.
    @discardableResult
    func moveFile(roomID: String, from: String, to: String) async throws -> MovedNote
    func createFolder(roomID: String, path: String) async throws
    @discardableResult
    func moveFolder(roomID: String, from: String, to: String) async throws -> MovedFolder
    /// Fails with `.notEmpty` for a folder with something inside, unless `recursive`.
    @discardableResult
    func deleteFolder(roomID: String, path: String, recursive: Bool) async throws -> DeletedFolder
}
