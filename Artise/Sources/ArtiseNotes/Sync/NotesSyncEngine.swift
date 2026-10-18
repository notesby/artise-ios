//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// `NotesRepository` over the Notes API and the phone's encrypted store, following the contract's
/// "Offline sync, step by step":
/// 1. edits are saved on the phone at once and queued with the version they started from;
/// 2. `sync` sends the queue in order; conflicts wait for the person instead of blocking other notes;
/// 3. then the tree is pulled with its ETag, updating changed files and dropping removed ones,
///    except files with local edits, which are never overwritten.
///
/// It behaves like the Android app's `NotesSyncEngine`, so both apps sync the same way.
public final class NotesSyncEngine: NotesRepository {
    static let privacyNoticeFlag = "privacy_notice_seen"
    
    let api: NotesAPIClient
    let store: NotesStore
    let locks = RoomLocks()
    let changeCenter = NotesChangeCenter()
    let now: @Sendable () -> Date
    let files: NotesFileOptions
    let uploads = UploadTracker()
    
    /// - Parameters:
    ///   - directory: where this account's encrypted notes live.
    ///   - cipher: encrypts everything written there.
    ///   - files: where photos and files live on the phone, and how they're prepared.
    public init(api: NotesAPIClient, directory: URL, cipher: NotesCipher, files: NotesFileOptions? = nil,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.api = api
        store = NotesStore(directory: directory, cipher: cipher)
        self.files = files ?? NotesFileOptions(directory: directory.appendingPathComponent("files"))
        self.now = now
    }
    
    // MARK: - Reading
    
    public func hasSeenPrivacyNotice() async throws -> Bool {
        try await store.index().flags.contains(Self.privacyNoticeFlag)
    }
    
    public func markPrivacyNoticeSeen() async throws {
        try await store.updateIndex { $0.flags.insert(Self.privacyNoticeFlag) }
    }
    
    public func cachedChats() async throws -> [NotesChat] {
        try await store.index().chats
    }
    
    public func refreshChats() async throws -> [NotesChat] {
        let chats = try await api.chats().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let known = try await Set(store.index().chats.map(\.roomID) + store.storedRoomIDs())
        let gone = known.filter { id in !chats.contains { $0.roomID == id } }
        try await store.updateIndex { $0.chats = chats }
        for roomID in gone {
            try await store.removeChat(roomID)
        }
        for chat in chats {
            if let record = try await store.chat(chat.roomID), record.name != chat.name {
                try await store.updateChat(chat.roomID) { $0.name = chat.name }
            }
        }
        return chats
    }
    
    public func files(roomID: String) async throws -> [LocalFile] {
        guard let record = try await store.chat(roomID) else { return [] }
        return record.files.values
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
            .map { Self.localFile($0, in: record) }
    }
    
    public func file(roomID: String, path: String) async throws -> LocalFile? {
        guard let record = try await store.chat(roomID), let file = record.files[path] else { return nil }
        return Self.localFile(file, in: record)
    }
    
    public func folders(roomID: String) async throws -> [String] {
        guard let record = try await store.chat(roomID) else { return [] }
        let fromFiles = record.files.keys.flatMap(Self.parentFolders)
        return Set(record.folders + fromFiles).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    public func edits(roomID: String) async throws -> [PendingEdit] {
        try await store.chat(roomID)?.edits.map(Self.pendingEdit) ?? []
    }
    
    public func changes(roomID: String) async -> AsyncStream<Void> {
        await changeCenter.changes(of: roomID)
    }
    
    // MARK: - Syncing
    
    @discardableResult
    public func sync(roomID: String) async throws -> SyncReport {
        try await locks.withLock(roomID) { () async throws -> SyncReport in
            let push: PushResult
            let pull: PullResult
            do {
                push = try await pushQueue(roomID)
                pull = try await pullTree(roomID)
            } catch {
                await changeCenter.notify(roomID)
                throw error
            }
            let report = SyncReport(sent: push.sent, needChoice: push.needChoice, updated: pull.updated, removed: pull.removed, failed: push.failed)
            if report.changedAnything {
                await changeCenter.notify(roomID)
            }
            if files.canPrefetch() {
                Task { await prefetchPhotos(roomID) }
            }
            return report
        }
    }
    
    @discardableResult
    public func onTreeChanged(roomID: String, tree: String) async throws -> SyncReport? {
        if try await store.chat(roomID)?.tree == tree {
            return nil
        }
        return try await sync(roomID: roomID)
    }
    
    // MARK: - Editing
    
    public func editNote(roomID: String, path: String, content: String) async throws {
        let seconds = nowSeconds
        let millis = nowMillis
        try await store.updateChat(roomID) { record in
            if record.files[path] == nil {
                // A note the phone never had: the edit creates it.
                record.files[path] = FileRecord(path: path, version: "", size: content.byteSize, modified: seconds, isNote: true, content: content)
                Self.addEdit(&record, kind: .save, path: path, content: content, baseVersion: nil, now: millis)
                return
            }
            Self.setContent(&record, path: path, content: content, modified: seconds)
            if let index = record.edits.lastIndex(where: { $0.path == path && $0.kind == .save && $0.state == .pending }) {
                // Coalesce: the earlier unsent edit keeps its base version, so the server still merges from there.
                record.edits[index].content = content
            } else {
                let version = record.files[path]?.version ?? ""
                Self.addEdit(&record, kind: .save, path: path, content: content, baseVersion: version.isEmpty ? nil : version, now: millis)
            }
        }
        await changeCenter.notify(roomID)
    }
    
    public func createNote(roomID: String, path: String, content: String) async throws {
        let seconds = nowSeconds
        let millis = nowMillis
        try await store.updateChat(roomID) { record in
            if record.files[path] != nil {
                throw NotesError.exists("A note named \(path) is already here", current: nil)
            }
            record.files[path] = FileRecord(path: path, version: "", size: content.byteSize, modified: seconds, isNote: true, content: content)
            Self.addEdit(&record, kind: .save, path: path, content: content, baseVersion: nil, now: millis)
        }
        await changeCenter.notify(roomID)
    }
    
    public func deleteFile(roomID: String, path: String) async throws {
        let millis = nowMillis
        try await store.updateChat(roomID) { record in
            guard let file = record.files[path] else { return }
            // Unsent edits of this file (and a waiting upload) no longer matter.
            for edit in record.edits where edit.path == path && edit.kind == .upload {
                if let waiting = edit.content {
                    try? FileManager.default.removeItem(at: files.pendingDirectory.appendingPathComponent(waiting))
                }
            }
            record.edits.removeAll { $0.path == path }
            record.files[path] = nil
            // A note created offline never reached the server: there's nothing to delete there.
            if !file.version.isEmpty {
                Self.addEdit(&record, kind: .delete, path: path, content: nil, baseVersion: file.version, now: millis)
            }
        }
        await changeCenter.notify(roomID)
    }
    
    // MARK: - Choices
    
    public func resolveConflict(roomID: String, editID: Int64, content: String) async throws {
        let seconds = nowSeconds
        try await store.updateChat(roomID) { record in
            guard let index = record.edits.firstIndex(where: { $0.id == editID }),
                  let serverVersion = record.edits[index].serverVersion else { return }
            let path = record.edits[index].path
            // The choice is now based on the server's version; it's saved on top of that.
            Self.setContent(&record, path: path, content: content, modified: seconds)
            record.files[path]?.version = serverVersion
            Self.requeue(&record.edits[index], path: path, content: content, baseVersion: serverVersion)
        }
        await changeCenter.notify(roomID)
    }
    
    public func keepDeletedNote(roomID: String, editID: Int64) async throws {
        try await store.updateChat(roomID) { record in
            guard let index = record.edits.firstIndex(where: { $0.id == editID }) else { return }
            let edit = record.edits[index]
            record.files[edit.path]?.version = ""
            Self.requeue(&record.edits[index], path: edit.path, content: edit.content, baseVersion: nil)
        }
        await changeCenter.notify(roomID)
    }
    
    public func saveUnderNewName(roomID: String, editID: Int64, newPath: String) async throws {
        let seconds = nowSeconds
        try await store.updateChat(roomID) { record in
            guard let index = record.edits.firstIndex(where: { $0.id == editID }) else { return }
            let edit = record.edits[index]
            if var file = record.files.removeValue(forKey: edit.path) {
                file.path = newPath
                file.version = ""
                record.files[newPath] = file
            }
            Self.requeue(&record.edits[index], path: newPath, content: edit.content, baseVersion: nil)
            // The other person's note keeps the original name.
            if let serverVersion = edit.serverVersion {
                let text = edit.serverContent
                record.files[edit.path] = FileRecord(path: edit.path, version: serverVersion, size: text?.byteSize ?? 0,
                                                     modified: seconds, isNote: true, content: text)
            }
        }
        await changeCenter.notify(roomID)
    }
    
    public func discardEdit(roomID: String, editID: Int64) async throws {
        let seconds = nowSeconds
        try await store.updateChat(roomID) { record in
            guard let index = record.edits.firstIndex(where: { $0.id == editID }) else { return }
            let edit = record.edits.remove(at: index)
            if edit.kind == .upload {
                // A refused upload: the waiting file and the attachment it would have become go.
                if let waiting = edit.content {
                    try? FileManager.default.removeItem(at: files.pendingDirectory.appendingPathComponent(waiting))
                }
                record.files[edit.path] = nil
            } else if let serverContent = edit.serverContent, let serverVersion = edit.serverVersion {
                // The server's copy is known: show it.
                Self.setContent(&record, path: edit.path, content: serverContent, modified: seconds)
                record.files[edit.path]?.version = serverVersion
            } else if edit.state == .deleted || (edit.kind == .save && edit.baseVersion == nil) {
                // Deleted on the server, or never sent: it's gone.
                record.files[edit.path] = nil
            } else {
                // Download the server's copy again with the next sync.
                record.files[edit.path] = nil
                record.etag = nil
            }
        }
        await changeCenter.notify(roomID)
    }
    
    // MARK: - Pushing (step 2)
    
    private struct PushResult {
        var sent = 0
        var needChoice = 0
        var failed = 0
    }
    
    enum PushOutcome {
        case sent
        case needsChoice
        /// Failed this time for a reason on the server's side: it stays queued and the push goes on.
        case retry
        case stop(NotesError)
    }
    
    /// Sends pending edits in order. A network or sign-in failure stops the push and leaves the rest queued.
    /// Any other failure of one edit sets it aside and goes on: one bad item never holds up the whole chat.
    private func pushQueue(_ roomID: String) async throws -> PushResult {
        guard let record = try await store.chat(roomID) else { return PushResult() }
        var result = PushResult()
        // An edit waiting for a choice holds back later edits to the same file, so they don't overtake it.
        var heldBack = Set(record.edits.filter { $0.state != .pending }.map(\.path))
        for edit in record.edits where edit.state == .pending {
            if heldBack.contains(edit.path) {
                continue
            }
            let outcome = switch edit.kind {
            case .save: try await pushSave(roomID, editID: edit.id)
            case .delete: try await pushDelete(roomID, edit: edit)
            case .upload: try await pushUpload(roomID, editID: edit.id)
            }
            switch outcome {
            case .sent:
                result.sent += 1
            case .needsChoice:
                result.needChoice += 1
                heldBack.insert(edit.path)
            case .retry:
                result.failed += 1
                heldBack.insert(edit.path)
            case .stop(let error):
                throw error
            }
        }
        return result
    }
    
    private func pushSave(_ roomID: String, editID: Int64) async throws -> PushOutcome {
        // Read now, not from the list taken when the push started, in case an earlier step changed it.
        guard let edit = try await store.chat(roomID)?.edits.first(where: { $0.id == editID }) else { return .sent }
        let saved: SavedNote
        do {
            saved = try await api.saveNote(roomID: roomID, path: edit.path, content: edit.content ?? "", baseVersion: edit.baseVersion)
        } catch {
            return try await handleFailure(roomID, editID: editID, error: error)
        }
        let seconds = nowSeconds
        try await store.updateChat(roomID) { record in
            record.files[edit.path]?.version = saved.version
            // The server merged this edit with someone else's: the merged text is now the note.
            if saved.merged, let merged = saved.content {
                Self.setContent(&record, path: edit.path, content: merged, modified: seconds)
            }
            record.edits.removeAll { $0.id == editID }
        }
        return .sent
    }
    
    private func pushDelete(_ roomID: String, edit: EditRecord) async throws -> PushOutcome {
        do {
            try await api.delete(roomID: roomID, path: edit.path, baseVersion: edit.baseVersion ?? "")
        } catch .notFound, .deleted {
            // Already gone on the server: that's what was wanted.
        } catch {
            return try await handleFailure(roomID, editID: edit.id, error: error)
        }
        try await store.updateChat(roomID) { $0.edits.removeAll { $0.id == edit.id } }
        return .sent
    }
    
    func handleFailure(_ roomID: String, editID: Int64, error: NotesError) async throws -> PushOutcome {
        func mark(_ state: EditState, current: ServerCopy? = nil, message: String? = nil) async throws {
            try await store.updateChat(roomID) { record in
                guard let index = record.edits.firstIndex(where: { $0.id == editID }) else { return }
                record.edits[index].state = state
                record.edits[index].serverVersion = current?.version
                record.edits[index].serverContent = current?.content
                record.edits[index].error = message
            }
        }
        
        switch error {
        case .conflict(_, let current):
            try await mark(.conflict, current: current)
            return .needsChoice
        case .deleted:
            try await mark(.deleted)
            return .needsChoice
        case .exists(_, let current):
            try await mark(.exists, current: current)
            return .needsChoice
        case .network, .unauthorized:
            // Every other edit would fail the same way: stop, and send the whole queue later.
            return .stop(error)
        case .server:
            // Something went wrong on the server's side with this one (a 5xx, a proxy limit, an unreadable answer).
            return .retry
        case .noChat, .badPath, .notFound, .tooBig, .inUse, .notEmpty, .notANote:
            // Retrying won't help.
            try await mark(.rejected, message: error.message)
            return .needsChoice
        }
    }
    
    // MARK: - Pulling (step 3)
    
    struct PullResult {
        var updated = 0
        var removed = 0
    }
    
    /// Pulls the tree with the cached ETag and updates what changed, never touching files with local edits.
    @discardableResult
    func pullTree(_ roomID: String) async throws -> PullResult {
        let response = try await api.tree(roomID: roomID, etag: store.chat(roomID)?.etag)
        guard case let .changed(tree, etag) = response else { return PullResult() }
        
        var result = PullResult()
        let local = try await store.chat(roomID)
        for file in tree.files where Self.needsDownload(file, local: local) {
            // Anything but "deleted meanwhile" stops the pull without saving the ETag, so the next sync tries again.
            if try await pullFile(roomID, file) {
                result.updated += 1
            }
        }
        
        let remotePaths = Set(tree.files.map(\.path))
        try await store.updateChat(roomID) { record in
            for (path, file) in record.files where !remotePaths.contains(path) {
                let hasEdits = record.edits.contains { $0.path == path }
                if !hasEdits, !file.version.isEmpty {
                    record.files[path] = nil
                    result.removed += 1
                }
            }
            record.folders = tree.folders
            record.tree = tree.tree
            record.etag = etag
        }
        return result
    }
    
    /// A file changed on the server, or a note whose text the phone doesn't have yet. Files with local edits are never overwritten.
    private static func needsDownload(_ file: NotesFile, local: ChatRecord?) -> Bool {
        guard let mine = local?.files[file.path] else { return true }
        if local?.edits.contains(where: { $0.path == file.path }) == true {
            return false
        }
        if mine.version != file.version {
            return true
        }
        return file.isNote && mine.content == nil
    }
    
    /// Stores one changed file; `false` when it was deleted between the tree and this request.
    private func pullFile(_ roomID: String, _ file: NotesFile) async throws -> Bool {
        guard file.isNote else {
            // Photos and documents download when opened; only the listing is kept.
            try await store.updateChat(roomID) { $0.files[file.path] = FileRecord(file, content: nil) }
            return true
        }
        let note: Note
        do {
            note = try await api.note(roomID: roomID, path: file.path)
        } catch .notFound {
            // Deleted between the tree and this request: the next tree won't list it.
            return false
        }
        var stored = FileRecord(file, content: note.content)
        stored.version = note.version
        try await store.updateChat(roomID) { [stored] record in record.files[file.path] = stored }
        return true
    }
    
    // MARK: - Helpers
    
    var nowSeconds: Int64 {
        Int64(now().timeIntervalSince1970)
    }
    
    var nowMillis: Int64 {
        Int64(now().timeIntervalSince1970 * 1000)
    }
    
    static func addEdit(_ record: inout ChatRecord, kind: EditKind, path: String, content: String?, baseVersion: String?, now: Int64) {
        record.edits.append(EditRecord(id: record.nextEditID, kind: kind, path: path, content: content, baseVersion: baseVersion,
                                       state: .pending, createdAt: now))
        record.nextEditID += 1
    }
    
    private static func requeue(_ edit: inout EditRecord, path: String, content: String?, baseVersion: String?) {
        edit.state = .pending
        edit.path = path
        edit.content = content
        edit.baseVersion = baseVersion
        edit.serverVersion = nil
        edit.serverContent = nil
        edit.error = nil
    }
    
    static func setContent(_ record: inout ChatRecord, path: String, content: String, modified: Int64) {
        record.files[path]?.content = content
        record.files[path]?.size = content.byteSize
        record.files[path]?.modified = modified
    }
    
    private static func localFile(_ file: FileRecord, in record: ChatRecord) -> LocalFile {
        LocalFile(path: file.path, version: file.version, size: file.size, modified: file.modified, isNote: file.isNote,
                  content: file.content, hasLocalEdits: record.edits.contains { $0.path == file.path })
    }
    
    private static func pendingEdit(_ edit: EditRecord) -> PendingEdit {
        let serverCopy = edit.serverVersion.map { ServerCopy(path: edit.path, version: $0, content: edit.serverContent) }
        return PendingEdit(id: edit.id, path: edit.path, kind: edit.kind, state: edit.state, content: edit.content,
                           serverCopy: serverCopy, error: edit.error)
    }
    
    /// "a/b/c.md" → ["a", "a/b"].
    static func parentFolders(of path: String) -> [String] {
        let parts = path.split(separator: "/").dropLast()
        return parts.indices.map { parts[...$0].joined(separator: "/") }
    }
}

extension FileRecord {
    init(_ file: NotesFile, content: String?) {
        self.init(path: file.path, version: file.version, size: file.size, modified: file.modified, isNote: file.isNote, content: content)
    }
}

extension String {
    var byteSize: Int64 {
        Int64(utf8.count)
    }
}
