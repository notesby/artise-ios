//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Synchronization

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
    /// Documents' text for search, by room and path, kept while the app runs.
    let texts = Mutex<[String: NotesDocumentText]>([:])
    let activityTracker = SyncActivityTracker()
    /// Counts what's done with notes, for people who said yes to usage statistics; never names or text.
    let track: @Sendable (NotesAnalyticsEvent) -> Void
    /// One line per sync with each step's time and counts, for the app's logs; never names or text.
    let log: @Sendable (String) -> Void
    
    /// - Parameters:
    ///   - directory: where this account's encrypted notes live.
    ///   - cipher: encrypts everything written there.
    ///   - files: where photos and files live on the phone, and how they're prepared.
    ///   - track: receives notes events for usage statistics; it decides whether they're sent.
    ///   - log: receives each sync's timing line.
    public init(api: NotesAPIClient, directory: URL, cipher: NotesCipher, files: NotesFileOptions? = nil,
                track: @escaping @Sendable (NotesAnalyticsEvent) -> Void = { _ in },
                log: @escaping @Sendable (String) -> Void = { _ in },
                now: @escaping @Sendable () -> Date = Date.init) {
        self.api = api
        store = NotesStore(directory: directory, cipher: cipher)
        self.files = files ?? NotesFileOptions(directory: directory.appendingPathComponent("files"))
        self.track = track
        self.log = log
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
    
    public func pages(roomID: String) async throws -> [NotesPage] {
        try await store.chat(roomID)?.pages ?? []
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
            let started = now()
            var timing = SyncTiming()
            do {
                // Text edits, then what others changed, then photos and files: a big upload never hides others' changes.
                let edits = try await timing.measure(\.editsMillis) { try await pushQueue(roomID, step: .edits) }
                pull = try await pullTree(roomID, timing: &timing)
                if pull.updated + pull.removed > 0 {
                    await changeCenter.notify(roomID)
                }
                push = try await edits + timing.measure(\.uploadsMillis) { try await pushQueue(roomID, step: .uploads) }
            } catch {
                log(timing.line(failed: true))
                await activityTracker.finish(roomID)
                await changeCenter.notify(roomID)
                throw error
            }
            let report = SyncReport(sent: push.sent, needChoice: push.needChoice, updated: pull.updated, removed: pull.removed, failed: push.failed)
            timing.sent = push.sent
            log(timing.line(failed: false))
            trackTiming(report, seconds: now().timeIntervalSince(started))
            if report.changedAnything {
                await changeCenter.notify(roomID)
            }
            if files.canPrefetch() {
                Task { await prefetchPhotos(roomID) }
            }
            return report
        }
    }
    
    /// Syncs every chat this phone already holds notes for, a few at a time: an unchanged chat costs one `304`.
    /// Chats never opened here aren't downloaded. Returns how many synced; failures wait for the next time.
    @discardableResult
    public func syncKnownChats(concurrency: Int = 3) async -> Int {
        let roomIDs = await store.storedRoomIDs()
        var synced = 0
        await withTaskGroup(of: Bool.self) { group in
            var pending = roomIDs[...]
            func startNext() {
                guard let roomID = pending.popFirst() else { return }
                group.addTask { await (try? self.sync(roomID: roomID)) != nil }
            }
            for _ in 0..<max(1, concurrency) {
                startNext()
            }
            for await succeeded in group {
                synced += succeeded ? 1 : 0
                startNext()
            }
        }
        return synced
    }
    
    public func knownRoomIDs() async -> [String] {
        await store.storedRoomIDs()
    }
    
    /// What a sync in progress is doing, for "Actualizando 12 notas…".
    public func activity(roomID: String) async -> SyncActivity {
        await activityTracker.activity(roomID)
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
        track(NotesAnalyticsEvent(.noteSaved))
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
        track(NotesAnalyticsEvent(.noteCreated))
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
        track(NotesAnalyticsEvent(.noteDeleted))
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
        track(NotesAnalyticsEvent(.choiceMade, kind: "combined"))
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
        track(NotesAnalyticsEvent(.choiceMade, kind: "kept_deleted"))
        try await store.updateChat(roomID) { record in
            guard let index = record.edits.firstIndex(where: { $0.id == editID }) else { return }
            let edit = record.edits[index]
            record.files[edit.path]?.version = ""
            Self.requeue(&record.edits[index], path: edit.path, content: edit.content, baseVersion: nil)
        }
        await changeCenter.notify(roomID)
    }
    
    public func saveUnderNewName(roomID: String, editID: Int64, newPath: String) async throws {
        track(NotesAnalyticsEvent(.choiceMade, kind: "new_name"))
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
        track(NotesAnalyticsEvent(.choiceMade, kind: "discarded"))
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
        
        static func + (lhs: PushResult, rhs: PushResult) -> PushResult {
            PushResult(sent: lhs.sent + rhs.sent, needChoice: lhs.needChoice + rhs.needChoice, failed: lhs.failed + rhs.failed)
        }
    }
    
    /// A sync sends text edits before pulling, and photos and files after it.
    enum PushStep {
        /// Saves and deletes, except those queued after an upload of the same file.
        case edits
        /// Uploads, and whatever waited behind them.
        case uploads
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
    private func pushQueue(_ roomID: String, step: PushStep) async throws -> PushResult {
        guard let record = try await store.chat(roomID) else { return PushResult() }
        var result = PushResult()
        // An edit waiting for a choice holds back later edits to the same file, so they don't overtake it.
        var heldBack = Set(record.edits.filter { $0.state != .pending }.map(\.path))
        // Each file's edits stay in order, and a photo goes up before the notes that show it (its name may change):
        // anything after an upload of that file, or a note embedding one, waits for the uploads step.
        let uploading = record.edits.filter { $0.state == .pending && $0.kind == .upload }.map(\.path)
        var afterUpload: Set<String> = []
        for edit in record.edits where edit.state == .pending {
            let embedsUpload = edit.kind == .save && !uploading.isEmpty
                && !NoteEmbeds.resolve(edit.content ?? "", paths: uploading).isEmpty
            let isUploadStep = edit.kind == .upload || afterUpload.contains(edit.path) || embedsUpload
            if isUploadStep {
                afterUpload.insert(edit.path)
            }
            if heldBack.contains(edit.path) || isUploadStep != (step == .uploads) {
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
        case .noChat, .badPath, .notFound, .tooBig, .inUse, .notEmpty, .notANote, .noPreview, .unreadable, .noText:
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
        var timing = SyncTiming()
        return try await pullTree(roomID, timing: &timing)
    }
    
    private func pullTree(_ roomID: String, timing: inout SyncTiming) async throws -> PullResult {
        let etag = try await store.chat(roomID)?.etag
        let response = try await timing.measure(\.treeMillis) { try await api.tree(roomID: roomID, etag: etag) }
        guard case let .changed(tree, etag) = response else { return PullResult() }
        timing.treeChanged = true
        timing.treeFiles = tree.files.count
        
        var result = PullResult()
        let local = try await store.chat(roomID)
        let changed = tree.files.filter { Self.needsDownload($0, local: local) }
        // Photos and documents download when opened; only their listing is kept, in one write.
        let listings = changed.filter { !$0.isNote }
        if !listings.isEmpty {
            try await store.updateChat(roomID) { record in
                for file in listings {
                    record.files[file.path] = FileRecord(file, content: nil)
                }
            }
            result.updated += listings.count
        }
        // Notes come down a few at a time, and each batch is written once: every write re-encrypts the chat's copy.
        let notes = changed.filter(\.isNote)
        var notesLeft = notes.count
        await setDownloading(roomID, notesLeft)
        for start in stride(from: 0, to: notes.count, by: Self.downloadBatch) {
            let batch = Array(notes[start..<min(start + Self.downloadBatch, notes.count)])
            // Anything but "deleted meanwhile" stops the pull without saving the ETag, so the next sync tries again.
            let downloaded = try await timing.measure(\.downloadMillis) { try await download(roomID, batch) }
            timing.batches += 1
            timing.notes += downloaded.count
            timing.noteBytes += downloaded.reduce(0) { $0 + $1.size }
            if !downloaded.isEmpty {
                try await timing.measure(\.saveMillis) {
                    try await store.updateChat(roomID) { record in
                        for stored in downloaded {
                            record.files[stored.path] = stored
                        }
                    }
                }
            }
            result.updated += downloaded.count
            notesLeft -= batch.count
            await setDownloading(roomID, notesLeft)
        }
        
        // Pages change with the tree, so they're fetched once per changed tree. A server without `/pages` keeps the last list.
        let pages = try? await api.pages(roomID: roomID)
        
        let remotePaths = Set(tree.files.map(\.path))
        try await store.updateChat(roomID) { record in
            if let pages {
                record.pages = pages
            }
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
    
    /// How many notes download at once, and are then written together.
    static let downloadBatch = 4
    
    /// The notes' text, all at once; a note deleted between the tree and its request is left out.
    private func download(_ roomID: String, _ files: [NotesFile]) async throws -> [FileRecord] {
        try await withThrowingTaskGroup(of: FileRecord?.self) { group in
            for file in files {
                group.addTask {
                    do {
                        let note = try await self.api.note(roomID: roomID, path: file.path)
                        var stored = FileRecord(file, content: note.content)
                        stored.version = note.version
                        return stored
                    } catch NotesError.notFound {
                        // Deleted between the tree and this request: the next tree won't list it.
                        return nil
                    }
                }
            }
            var downloaded: [FileRecord] = []
            for try await stored in group {
                if let stored {
                    downloaded.append(stored)
                }
            }
            return downloaded
        }
    }
    
    /// Shows the count only while several notes come down, so a one-note update doesn't flash a line.
    private func setDownloading(_ roomID: String, _ count: Int) async {
        if await activityTracker.setDownloading(roomID, count) {
            await changeCenter.notify(roomID)
        }
    }
    
    /// How long a sync took and how much it moved, in coarse groups; only syncs that did something, or took a while.
    private func trackTiming(_ report: SyncReport, seconds: TimeInterval) {
        guard report.sent + report.updated > 0 || seconds >= 3 else { return }
        track(NotesAnalyticsEvent(.syncFinished, values: ["seconds": Self.secondsGroup(seconds),
                                                          "downloaded": Self.countGroup(report.updated),
                                                          "sent": Self.countGroup(report.sent)]))
    }
    
    static func secondsGroup(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<1: "0-1"
        case ..<3: "1-3"
        case ..<10: "3-10"
        case ..<30: "10-30"
        default: "30+"
        }
    }
    
    static func countGroup(_ count: Int) -> String {
        switch count {
        case ..<1: "0"
        case ..<6: "1-5"
        case ..<21: "6-20"
        default: "21+"
        }
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
