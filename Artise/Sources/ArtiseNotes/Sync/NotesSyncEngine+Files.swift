//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Where photos and files live on the phone, and how they're prepared.
public struct NotesFileOptions: Sendable {
    /// Room on the phone for downloaded photos and files; files waiting to upload aren't counted or removed.
    public static let maxCacheBytes: Int64 = 300 * 1024 * 1024
    /// Bigger photos only download when their note is opened.
    public static let maxPrefetchBytes: Int64 = 15 * 1024 * 1024
    public static let attachmentsFolder = "attachments"
    
    /// Downloaded photos and files, trimmed to `maxCacheBytes`.
    public let cacheDirectory: URL
    /// Photos and files added on this phone, kept until they're uploaded.
    public let pendingDirectory: URL
    /// Turns photos into JPEGs before they upload (HEIC, or big ones); `nil` keeps the file as it is.
    public let convertPhoto: @Sendable (Data, String) -> Data?
    /// Whether photos may download ahead of time: on Wi-Fi, never on mobile data.
    public let canPrefetch: @Sendable () -> Bool
    /// How much the downloaded copies may take.
    public let cacheLimit: Int64
    
    public init(cacheDirectory: URL, pendingDirectory: URL,
                convertPhoto: @escaping @Sendable (Data, String) -> Data? = { _, _ in nil },
                canPrefetch: @escaping @Sendable () -> Bool = { false },
                cacheLimit: Int64 = NotesFileOptions.maxCacheBytes) {
        self.cacheDirectory = cacheDirectory
        self.pendingDirectory = pendingDirectory
        self.convertPhoto = convertPhoto
        self.canPrefetch = canPrefetch
        self.cacheLimit = cacheLimit
    }
    
    init(directory: URL) {
        self.init(cacheDirectory: directory.appendingPathComponent("cache"), pendingDirectory: directory.appendingPathComponent("pending"))
    }
}

/// How an upload is going.
public enum UploadStatus: Equatable, Sendable {
    /// Queued: it goes up with the next sync that has a connection.
    case waiting
    /// Being sent right now.
    case uploading
    /// The last try failed on the server's side; it's tried again with the next sync.
    case retrying
    /// The server refused it for good (too big, a bad name): it won't be sent.
    case failed
}

/// A photo or file in a chat's notes, with the notes that use it.
public struct MediaFile: Equatable, Sendable {
    public let path: String
    public let size: Int64
    public let modified: Int64
    /// The notes that show or link it; empty when no note uses it.
    public let usedBy: [String]
    /// Added on this phone and not on the server yet.
    public let upload: UploadStatus?
}

/// Uploads being sent right now, and those whose last try failed on the server's side, by edit id.
actor UploadTracker {
    private var uploading: Set<Int64> = []
    private var retrying: Set<Int64> = []
    
    func status(of editID: Int64) -> UploadStatus {
        if uploading.contains(editID) {
            return .uploading
        }
        if retrying.contains(editID) {
            return .retrying
        }
        return .waiting
    }
    
    func start(_ editID: Int64) {
        uploading.insert(editID)
    }
    
    func finish(_ editID: Int64, needsRetry: Bool) {
        uploading.remove(editID)
        if needsRetry {
            retrying.insert(editID)
        } else {
            retrying.remove(editID)
        }
    }
    
    func forget(_ editID: Int64) {
        uploading.remove(editID)
        retrying.remove(editID)
    }
}

public extension NotesSyncEngine {
    // MARK: - Adding
    
    /// Adds a photo or file to the chat's `attachments/` folder, where Ari keeps files too, under a name not taken
    /// yet. It's kept on the phone at once (so it shows offline) and uploaded with the next sync, before the note
    /// edits that embed it. Returns the attachment's path.
    func addAttachment(roomID: String, fileName: String, data: Data, contentType: String) async throws -> String {
        let waitingName = UUID().uuidString + Self.extensionWithDot(fileName)
        try FileManager.default.createDirectory(at: files.pendingDirectory, withIntermediateDirectories: true)
        try data.write(to: files.pendingDirectory.appendingPathComponent(waitingName), options: .atomic)
        let seconds = nowSeconds
        let millis = nowMillis
        let path = try await store.updateChat(roomID) { record in
            let path = Self.freeAttachmentPath(fileName, taken: Set(record.files.keys.map { $0.lowercased() }))
            // Listed at once without a version: it shows from the phone until it's uploaded.
            record.files[path] = FileRecord(path: path, version: "", size: Int64(data.count), modified: seconds, isNote: false, content: nil)
            record.edits.append(EditRecord(id: record.nextEditID, kind: .upload, path: path, content: waitingName, baseVersion: nil,
                                           state: .pending, createdAt: millis, contentType: contentType))
            record.nextEditID += 1
            return path
        }
        await changeCenter.notify(roomID)
        return path
    }
    
    // MARK: - Opening
    
    /// The photo or file as a file on the phone, downloaded once and kept for as long as it doesn't change.
    func attachment(roomID: String, path: String) async throws -> URL {
        if let waiting = try await waitingUpload(roomID: roomID, path: path) {
            // Still waiting to upload: the phone's copy is the only one.
            return waiting
        }
        let version = try await store.chat(roomID)?.files[path]?.version ?? ""
        let cached = cacheURL(roomID: roomID, path: path, version: version)
        if !version.isEmpty, FileManager.default.fileExists(atPath: cached.path) {
            // Recently used: the last to go when the phone's copies are trimmed.
            try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: cached.path)
            return cached
        }
        let data = try await api.raw(roomID: roomID, path: path)
        try FileManager.default.createDirectory(at: files.cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: cached, options: .atomic)
        trimCache()
        return cached
    }
    
    /// The photo or file's copy on the phone, if it's there already; never downloads.
    func cachedAttachment(roomID: String, path: String) async throws -> URL? {
        if let waiting = try await waitingUpload(roomID: roomID, path: path) {
            return waiting
        }
        guard let version = try await store.chat(roomID)?.files[path]?.version, !version.isEmpty else { return nil }
        let cached = cacheURL(roomID: roomID, path: path, version: version)
        return FileManager.default.fileExists(atPath: cached.path) ? cached : nil
    }
    
    // MARK: - Uploads and media
    
    /// Photos and files added on this phone and not on the server yet, by path.
    func uploads(roomID: String) async throws -> [String: UploadStatus] {
        var statuses: [String: UploadStatus] = [:]
        for edit in try await store.chat(roomID)?.edits ?? [] where edit.kind == .upload {
            statuses[edit.path] = edit.state == .pending ? await uploads.status(of: edit.id) : .failed
        }
        return statuses
    }
    
    /// Every photo and file in the chat's notes, with the notes that use each one (from the notes on the phone).
    func media(roomID: String) async throws -> [MediaFile] {
        let all = try await files(roomID: roomID)
        let paths = all.map(\.path)
        let notes = all.filter { $0.isNote && $0.content != nil }.map { (path: $0.path, text: $0.content ?? "") }
        let usedBy = NoteReferences.index(notes: notes, paths: paths)
        let statuses = try await uploads(roomID: roomID)
        return all.filter { !$0.isNote }.map { file in
            MediaFile(path: file.path, size: file.size, modified: file.modified, usedBy: usedBy[file.path] ?? [], upload: statuses[file.path])
        }
    }
    
    /// Tries a waiting, failing or refused upload again now.
    func retryUpload(roomID: String, path: String) async throws {
        let editID = try await store.updateChat(roomID) { record -> Int64? in
            guard let index = record.edits.firstIndex(where: { $0.kind == .upload && $0.path == path }) else { return nil }
            record.edits[index].state = .pending
            record.edits[index].error = nil
            return record.edits[index].id
        }
        if let editID {
            await uploads.forget(editID)
        }
        await changeCenter.notify(roomID)
        syncInBackground(roomID: roomID)
    }
    
    /// Drops an upload not sent yet, and takes it out of the notes that embed it.
    func cancelUpload(roomID: String, path: String) async throws {
        // Waits for a push in progress: an upload is never dropped halfway through.
        try await locks.withLock(roomID) { () async throws in
            let millis = nowMillis
            let seconds = nowSeconds
            let pending = files.pendingDirectory
            let editID = try await store.updateChat(roomID) { record -> Int64? in
                guard let index = record.edits.firstIndex(where: { $0.kind == .upload && $0.path == path }) else { return nil }
                let edit = record.edits.remove(at: index)
                if let waiting = edit.content {
                    try? FileManager.default.removeItem(at: pending.appendingPathComponent(waiting))
                }
                record.files[path] = nil
                Self.rewriteNotes(&record, now: millis, seconds: seconds) { NoteEmbedRemover.remove(path, from: $0) }
                return edit.id
            }
            if let editID {
                await uploads.forget(editID)
            }
        }
        await changeCenter.notify(roomID)
    }
    
    /// Deletes a photo or file. It needs a connection: the notes are refreshed and the server is asked which notes use
    /// it, so nothing in use is deleted by mistake. When notes use it, it fails with `.inUse`, unless
    /// `removeFromNotes`, which first takes it out of those notes. A file not uploaded yet is just dropped.
    func deleteMedia(roomID: String, path: String, removeFromNotes: Bool) async throws {
        if try await uploads(roomID: roomID)[path] != nil {
            try await cancelUpload(roomID: roomID, path: path)
            return
        }
        // The latest notes first, so a note that started using the file since isn't missed.
        try await sync(roomID: roomID)
        let onServer = try await api.links(roomID: roomID, path: path).backlinks.map(\.path)
        let all = try await files(roomID: roomID)
        let paths = all.map(\.path)
        let onPhone = all.filter { $0.isNote && NoteReferences.filesUsed(in: $0.content ?? "", paths: paths).contains(path) }.map(\.path)
        let usedBy = Set(onServer + onPhone).sorted()
        if !usedBy.isEmpty, !removeFromNotes {
            throw NotesError.inUse("Used by \(usedBy.count) notes", usedBy: usedBy)
        }
        for note in usedBy {
            guard let content = all.first(where: { $0.path == note })?.content else { continue }
            let updated = NoteReferences.remove(path, from: content, paths: paths)
            if updated != content {
                try await editNote(roomID: roomID, path: note, content: updated)
            }
        }
        // Queued after the notes' changes, so the server sees those first.
        try await deleteFile(roomID: roomID, path: path)
        syncInBackground(roomID: roomID)
    }
    
    // MARK: - Renaming and moving
    
    /// Renames or moves a note, photo or file right away on the server; needs a connection and no unsent changes to it.
    func moveFile(roomID: String, from: String, to: String) async throws -> MovedNote {
        try await locks.withLock(roomID) { () async throws -> MovedNote in
            guard let record = try await store.chat(roomID), let file = record.files[from] else {
                throw NotesError.notFound("No file named \(from)")
            }
            if file.version.isEmpty || record.edits.contains(where: { $0.path == from }) {
                throw NotesError.conflict("\(from) has changes that haven't been sent yet. Sync first.", current: nil)
            }
            let moved = try await api.move(roomID: roomID, from: from, to: to, baseVersion: file.version)
            try await store.updateChat(roomID) { record in
                if var renamed = record.files.removeValue(forKey: from) {
                    renamed.path = to
                    renamed.version = moved.version
                    record.files[to] = renamed
                }
            }
            // The server rewrote links in other notes; pull them.
            if !moved.linksUpdated.isEmpty {
                try await pullTree(roomID)
            }
            await changeCenter.notify(roomID)
            return moved
        }
    }
    
    /// Creates a folder (and any missing parents) on the server; needs a connection.
    func createFolder(roomID: String, path: String) async throws {
        try await api.createFolder(roomID: roomID, path: path)
        try await store.updateChat(roomID) { record in
            record.folders = Array(Set(record.folders + Self.parentFolders(of: path + "/x") + [path])).sorted()
        }
        await changeCenter.notify(roomID)
    }
    
    /// Moves or renames a folder with everything inside (the server updates the links); needs a connection.
    func moveFolder(roomID: String, from: String, to: String) async throws -> MovedFolder {
        try await locks.withLock(roomID) { () async throws -> MovedFolder in
            // Like a single move: changes inside must reach the server first, or the move would leave them behind.
            try await requireNoUnsentChanges(roomID: roomID, inFolder: from)
            let moved = try await api.moveFolder(roomID: roomID, from: from, to: to)
            try await store.updateChat(roomID) { record in
                for file in moved.moved {
                    if var renamed = record.files.removeValue(forKey: file.from) {
                        renamed.path = file.to
                        renamed.version = file.version
                        record.files[file.to] = renamed
                    }
                }
                let renamedFolders = record.folders.map { folder in
                    folder == from || folder.hasPrefix(from + "/") ? to + folder.dropFirst(from.count) : folder
                }
                record.folders = Array(Set(renamedFolders + Self.parentFolders(of: to + "/x") + [to])).sorted()
            }
            if !moved.linksUpdated.isEmpty {
                try await pullTree(roomID)
            }
            await changeCenter.notify(roomID)
            return moved
        }
    }
    
    /// Deletes a folder; needs a connection. One that isn't empty fails with `.notEmpty` unless `recursive`: then its
    /// notes are deleted (their history keeps them) and its photos and files go to the trash.
    func deleteFolder(roomID: String, path: String, recursive: Bool) async throws -> DeletedFolder {
        try await locks.withLock(roomID) { () async throws -> DeletedFolder in
            try await requireNoUnsentChanges(roomID: roomID, inFolder: path)
            let deleted = try await api.deleteFolder(roomID: roomID, path: path, recursive: recursive)
            try await store.updateChat(roomID) { record in
                for key in record.files.keys where key.hasPrefix(path + "/") {
                    record.files[key] = nil
                }
                record.folders.removeAll { $0 == path || $0.hasPrefix(path + "/") }
            }
            await changeCenter.notify(roomID)
            return deleted
        }
    }
    
    func history(roomID: String, path: String) async throws -> [NoteVersion] {
        try await api.history(roomID: roomID, path: path)
    }
    
    func changeHistory(roomID: String, before: String?) async throws -> NotesChangesPage {
        try await api.changes(roomID: roomID, before: before)
    }
    
    func noteAt(roomID: String, path: String, commit: String) async throws -> Note {
        try await api.note(roomID: roomID, path: path, atCommit: commit)
    }
    
    /// Starts a sync that goes on if the screen that asked for it closes. Failures are silent: the queue stays.
    func syncInBackground(roomID: String) {
        Task { _ = try? await sync(roomID: roomID) }
    }
}

// MARK: - Internals

extension NotesSyncEngine {
    /// Uploads a waiting photo or file. A photo is turned into a JPEG first when it needs to be. If someone uploaded a
    /// file with the same name meanwhile, it takes the next free name and the notes that embed it are changed to match.
    func pushUpload(_ roomID: String, editID: Int64) async throws -> PushOutcome {
        await uploads.start(editID)
        await changeCenter.notify(roomID)
        let outcome: PushOutcome
        do {
            outcome = try await sendUpload(roomID, editID: editID)
        } catch {
            await uploads.finish(editID, needsRetry: true)
            await changeCenter.notify(roomID)
            throw error
        }
        if case .retry = outcome {
            await uploads.finish(editID, needsRetry: true)
        } else {
            await uploads.finish(editID, needsRetry: false)
        }
        await changeCenter.notify(roomID)
        return outcome
    }
    
    private func sendUpload(_ roomID: String, editID: Int64) async throws -> PushOutcome {
        guard let edit = try await store.chat(roomID)?.edits.first(where: { $0.id == editID }) else { return .sent }
        let pending = files.pendingDirectory
        guard let waitingName = edit.content, let data = try? Data(contentsOf: pending.appendingPathComponent(waitingName)) else {
            try await store.updateChat(roomID) { record in
                if let index = record.edits.firstIndex(where: { $0.id == editID }) {
                    record.edits[index].state = .rejected
                    record.edits[index].error = "The file is no longer on this phone"
                }
            }
            return .needsChoice
        }
        var bytes = data
        var path = edit.path
        var contentType = Self.mimeType(of: path) ?? edit.contentType ?? "application/octet-stream"
        // The name says what the file is now (a converted photo becomes .jpg), so it's never converted twice.
        if let jpeg = files.convertPhoto(bytes, contentType) {
            let jpegName = UUID().uuidString + ".jpg"
            try jpeg.write(to: pending.appendingPathComponent(jpegName), options: .atomic)
            try? FileManager.default.removeItem(at: pending.appendingPathComponent(waitingName))
            let newPath = try await renameUpload(roomID, editID: editID, from: path, toName: Self.jpegName(NotesFolderEntries.fileName(path)), waitingName: jpegName)
            bytes = jpeg
            path = newPath
            contentType = "image/jpeg"
        }
        for _ in 0..<5 {
            let version: String
            do {
                version = try await api.saveRaw(roomID: roomID, path: path, data: bytes, contentType: contentType, baseVersion: nil)
            } catch .exists {
                path = try await renameUpload(roomID, editID: editID, from: path, toName: NotesFolderEntries.fileName(path), waitingName: nil)
                continue
            } catch {
                return try await handleFailure(roomID, editID: editID, error: error)
            }
            let waiting = try await store.chat(roomID)?.edits.first { $0.id == editID }?.content
            try await store.updateChat(roomID) { record in
                record.files[path]?.version = version
                record.edits.removeAll { $0.id == editID }
            }
            // The uploaded copy is kept as the downloaded one, so it never downloads again.
            try FileManager.default.createDirectory(at: files.cacheDirectory, withIntermediateDirectories: true)
            try bytes.write(to: cacheURL(roomID: roomID, path: path, version: version), options: .atomic)
            if let waiting {
                try? FileManager.default.removeItem(at: pending.appendingPathComponent(waiting))
            }
            return .sent
        }
        return try await handleFailure(roomID, editID: editID, error: .exists("No free name for \(edit.path)", current: nil))
    }
    
    /// Moves a waiting upload to a free name based on `toName`, and points the notes that embed it at the new name:
    /// unsent edits are changed, and a note already sent gets a new edit, so no note points at a name that won't exist.
    private func renameUpload(_ roomID: String, editID: Int64, from: String, toName: String, waitingName: String?) async throws -> String {
        let millis = nowMillis
        let seconds = nowSeconds
        let newPath = try await store.updateChat(roomID) { record -> String in
            let taken = Set(record.files.keys.map { $0.lowercased() }).union([from.lowercased()])
            let newPath = Self.freeAttachmentPath(toName, taken: taken)
            if var file = record.files.removeValue(forKey: from) {
                file.path = newPath
                record.files[newPath] = file
            }
            if let index = record.edits.firstIndex(where: { $0.id == editID }) {
                record.edits[index].path = newPath
                if let waitingName {
                    record.edits[index].content = waitingName
                }
            }
            let oldName = NotesFolderEntries.fileName(from)
            let newName = NotesFolderEntries.fileName(newPath)
            Self.rewriteNotes(&record, now: millis, seconds: seconds) {
                $0.replacingOccurrences(of: "[[" + oldName, with: "[[" + newName).replacingOccurrences(of: "[[" + from, with: "[[" + newPath)
            }
            return newPath
        }
        await changeCenter.notify(roomID)
        return newPath
    }
    
    /// Changes every note `change` applies to, and queues the change to be sent.
    static func rewriteNotes(_ record: inout ChatRecord, now: Int64, seconds: Int64, _ change: (String) -> String) {
        for (path, file) in record.files where file.isNote {
            guard let content = file.content else { continue }
            let updated = change(content)
            guard updated != content else { continue }
            setContent(&record, path: path, content: updated, modified: seconds)
            if let index = record.edits.lastIndex(where: { $0.path == path && $0.kind == .save && $0.state == .pending }) {
                record.edits[index].content = change(record.edits[index].content ?? "")
            } else {
                addEdit(&record, kind: .save, path: path, content: updated, baseVersion: file.version.isEmpty ? nil : file.version, now: now)
            }
        }
    }
    
    /// Downloads the photos embedded in the chat's notes that aren't on the phone yet, so notes show them offline.
    /// Photos only (documents download when opened), none over `maxPrefetchBytes`, and only while prefetching is allowed.
    func prefetchPhotos(_ roomID: String) async {
        guard let record = try? await store.chat(roomID) else { return }
        let paths = Array(record.files.keys)
        var wanted: Set<String> = []
        for file in record.files.values where file.isNote {
            wanted.formUnion(NoteEmbeds.resolve(file.content ?? "", paths: paths).values)
        }
        let photos = wanted.compactMap { record.files[$0] }.filter { file in
            NotesFolderEntries.isImage(file.path) && !file.version.isEmpty && file.size <= NotesFileOptions.maxPrefetchBytes
                && !FileManager.default.fileExists(atPath: cacheURL(roomID: roomID, path: file.path, version: file.version).path)
        }
        for photo in photos.sorted(by: { $0.path < $1.path }) {
            guard files.canPrefetch() else { return }
            // A failure just means it downloads when the note is opened.
            _ = try? await attachment(roomID: roomID, path: photo.path)
        }
    }
    
    /// Keeps the phone's copies under the cache limit (300 MB), removing the least recently used first.
    func trimCache() {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? manager.contentsOfDirectory(at: files.cacheDirectory, includingPropertiesForKeys: keys) else { return }
        let cached = urls.compactMap { url -> (url: URL, date: Date, size: Int64)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }
        .sorted { $0.date < $1.date }
        var total = cached.reduce(0) { $0 + $1.size }
        for file in cached where total > files.cacheLimit {
            try? manager.removeItem(at: file.url)
            total -= file.size
        }
    }
    
    /// One file per attachment and version: a changed photo is downloaded again, an unchanged one never.
    func cacheURL(roomID: String, path: String, version: String) -> URL {
        let key = Self.stableHash(roomID + "/" + path) + "-" + String(version.prefix(12))
        return files.cacheDirectory.appendingPathComponent(key + Self.extensionWithDot(path))
    }
    
    private func waitingUpload(roomID: String, path: String) async throws -> URL? {
        let edit = try await store.chat(roomID)?.edits.first { $0.kind == .upload && $0.path == path && $0.state == .pending }
        return edit?.content.map { files.pendingDirectory.appendingPathComponent($0) }
    }
    
    private func requireNoUnsentChanges(roomID: String, inFolder folder: String) async throws {
        let record = try await store.chat(roomID)
        let hasUnsent = record?.files.values.contains { file in
            file.path.hasPrefix(folder + "/") && (file.version.isEmpty || record?.edits.contains { $0.path == file.path } == true)
        } ?? false
        if hasUnsent {
            throw NotesError.conflict("\(folder) holds changes that haven't been sent yet. Sync first.", current: nil)
        }
    }
    
    /// "attachments/foto.jpg", or "attachments/foto (2).jpg" if that's taken. Folders and hidden names are refused.
    static func freeAttachmentPath(_ fileName: String, taken: Set<String>) -> String {
        var clean = NotesFolderEntries.fileName(fileName).trimmingCharacters(in: .whitespaces)
        while clean.hasPrefix(".") {
            clean.removeFirst()
        }
        if clean.isEmpty {
            clean = "archivo"
        }
        let ext = extensionWithDot(clean)
        let base = ext.isEmpty ? clean : String(clean.dropLast(ext.count))
        var number = 1
        while true {
            let candidate = NotesFileOptions.attachmentsFolder + "/" + (number == 1 ? base : "\(base) (\(number))") + ext
            if !taken.contains(candidate.lowercased()) {
                return candidate
            }
            number += 1
        }
    }
    
    /// ".jpg" for "foto.jpg"; "" when there's no short extension.
    static func extensionWithDot(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        let ext = name[name.index(after: dot)...]
        return (1...5).contains(ext.count) && !ext.contains("/") ? "." + ext : ""
    }
    
    /// "IMG_1234.heic" → "IMG_1234.jpg".
    static func jpegName(_ name: String) -> String {
        let ext = extensionWithDot(name)
        return (ext.isEmpty ? name : String(name.dropLast(ext.count))) + ".jpg"
    }
    
    /// The type of a photo by its name, or `nil` for anything else.
    static func mimeType(of name: String) -> String? {
        switch extensionWithDot(name).lowercased() {
        case ".heic": "image/heic"
        case ".heif": "image/heif"
        case ".avif": "image/avif"
        case ".jpg", ".jpeg": "image/jpeg"
        case ".png": "image/png"
        case ".webp": "image/webp"
        default: nil
        }
    }
    
    /// A short name that stays the same across launches and platforms (FNV-1a, twice), for cache file names.
    static func stableHash(_ text: String) -> String {
        func fnv(_ seed: UInt64) -> UInt64 {
            var hash = seed
            for byte in text.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100_0000_01B3
            }
            return hash
        }
        return String(format: "%016llx%08llx", fnv(0xCBF2_9CE4_8422_2325), fnv(0x8422_2325_CBF2_9CE4) >> 32)
    }
}
