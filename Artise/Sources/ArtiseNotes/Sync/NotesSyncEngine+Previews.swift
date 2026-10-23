//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension NotesSyncEngine {
    /// A preview for lists: a PDF's first page or a photo as a small PNG on the phone, or a text file's first lines.
    ///
    /// Fetched once per file version and size and kept with the downloaded photos (trimmed with them). A changed
    /// file is asked for with the last picture's ETag, so an unchanged picture costs a `304` and no bytes. A file the
    /// server has no preview for (an Office file, one it can't read) is remembered as such per version, so lists
    /// never ask about it again. A file that isn't there fails with `.notFound`.
    func preview(roomID: String, path: String, size: Int) async throws -> NotePreview? {
        try await preview(roomID: roomID, path: path, size: size, version: nil)
    }
    
    /// `version` comes from a document card when there is one: the chat's notes may not be on the phone yet, and a
    /// file kept under no version would never show its newer pictures.
    func preview(roomID: String, path: String, size: Int, version: String?) async throws -> NotePreview? {
        let known = try await store.chat(roomID)?.files[path]?.version
        let version = version ?? known ?? ""
        let names = PreviewNames(directory: files.cacheDirectory, roomID: roomID, path: path, version: version, size: size)
        let manager = FileManager.default
        if manager.fileExists(atPath: names.picture.path) {
            // Recently used: the last to go when the phone's copies are trimmed.
            try? manager.setAttributes([.modificationDate: now()], ofItemAtPath: names.picture.path)
            return .image(names.picture)
        }
        if let text = try? String(contentsOf: names.text, encoding: .utf8) {
            return .text(text)
        }
        if manager.fileExists(atPath: names.none.path) {
            return nil
        }
        try manager.createDirectory(at: files.cacheDirectory, withIntermediateDirectories: true)
        let lastETag = Self.readETag(names.etag)
        do {
            switch try await api.preview(roomID: roomID, path: path, size: size, etag: lastETag?.etag) {
            case .image(let data, let etag):
                try data.write(to: names.picture, options: .atomic)
                Self.writeETag(names.etag, etag: etag, version: version)
            case .text(let text):
                try Data(text.utf8).write(to: names.text, options: .atomic)
                return .text(text)
            case .notModified:
                // The picture of the version we had is still right: it's kept under the new version's name.
                let previous = names.withVersion(lastETag?.version ?? "").picture
                guard manager.fileExists(atPath: previous.path) else {
                    try? manager.removeItem(at: names.etag)
                    return try await preview(roomID: roomID, path: path, size: size, version: version)
                }
                try manager.copyItem(at: previous, to: names.picture)
                Self.writeETag(names.etag, etag: lastETag?.etag, version: version)
            }
        } catch NotesError.noPreview, NotesError.unreadable {
            try? Data().write(to: names.none, options: .atomic)
            return nil
        }
        trimCache()
        return .image(names.picture)
    }
    
    /// A document's text page by page, for search. Asked for once per file version while the app runs.
    func documentText(roomID: String, path: String) async throws -> NotesDocumentText {
        let key = roomID + "\u{0}" + path
        let version = try await store.chat(roomID)?.files[path]?.version
        if let cached = texts.withLock({ $0[key] }), version == nil || cached.version == version {
            return cached
        }
        let text = try await api.text(roomID: roomID, path: path)
        texts.withLock { $0[key] = text }
        return text
    }
    
    func officePDF(roomID: String, path: String) async throws -> URL {
        let version = try await store.chat(roomID)?.files[path]?.version ?? ""
        let url = files.cacheDirectory.appendingPathComponent("converted-" + Self.stableHash(roomID + "/" + path) + "-" + version + ".pdf")
        let manager = FileManager.default
        if !version.isEmpty, manager.fileExists(atPath: url.path) {
            try? manager.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
            return url
        }
        let data = try await api.pdf(roomID: roomID, path: path)
        try manager.createDirectory(at: files.cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        trimCache()
        return url
    }
    
    // MARK: - Internals
    
    /// Where a preview and what's known about it live, next to the downloaded photos.
    struct PreviewNames {
        let directory: URL
        let roomID: String
        let path: String
        let version: String
        let size: Int
        
        private var base: String {
            "preview-" + NotesSyncEngine.stableHash(roomID + "/" + path) + "-" + version + "-" + String(size)
        }
        
        var picture: URL {
            directory.appendingPathComponent(base + ".png")
        }
        
        var text: URL {
            directory.appendingPathComponent(base + ".txt")
        }
        
        /// Marks a version the server has no preview for.
        var none: URL {
            directory.appendingPathComponent(base + ".none")
        }
        
        /// The last picture's ETag and the version it was for, shared by every version of the file at this size.
        var etag: URL {
            directory.appendingPathComponent("preview-" + NotesSyncEngine.stableHash(roomID + "/" + path) + "-" + String(size) + ".etag")
        }
        
        func withVersion(_ version: String) -> PreviewNames {
            PreviewNames(directory: directory, roomID: roomID, path: path, version: version, size: size)
        }
    }
    
    private static func readETag(_ url: URL) -> (etag: String, version: String)? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parts = text.components(separatedBy: "\n")
        guard let etag = parts.first, !etag.isEmpty else { return nil }
        return (etag, parts.count > 1 ? parts[1] : "")
    }
    
    private static func writeETag(_ url: URL, etag: String?, version: String) {
        guard let etag, !etag.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? Data((etag + "\n" + version).utf8).write(to: url, options: .atomic)
    }
}
