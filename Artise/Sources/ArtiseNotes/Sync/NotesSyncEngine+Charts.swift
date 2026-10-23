//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension NotesSyncEngine {
    /// The picture of a chart or dashboard as last drawn at this size and mode, if the phone has one. Never asks the
    /// server: lists and cards show it at once, then ask with `drawing`.
    func cachedDrawing(roomID: String, path: String, size: Int, mode: NoteDrawingMode) -> URL? {
        let names = DrawingNames(directory: files.cacheDirectory, roomID: roomID, path: path, size: size, mode: mode)
        return FileManager.default.fileExists(atPath: names.picture.path) ? names.picture : nil
    }
    
    /// A chart's or dashboard's picture as the server draws it now. Unlike other previews it's never trusted by the
    /// file's version alone: a chart that reads the chat's records changes when they do. So it's always asked for with
    /// the last picture's ETag, and an unchanged one costs a `304` and no bytes. Light and dark are kept apart.
    /// `nil` when the server can't draw it (`422`, a kind it has no picture for).
    func drawing(roomID: String, path: String, size: Int, mode: NoteDrawingMode) async throws -> URL? {
        let names = DrawingNames(directory: files.cacheDirectory, roomID: roomID, path: path, size: size, mode: mode)
        let manager = FileManager.default
        let hasPicture = manager.fileExists(atPath: names.picture.path)
        let etag = hasPicture ? (try? String(contentsOf: names.etag, encoding: .utf8)) : nil
        do {
            switch try await api.preview(roomID: roomID, path: path, size: size, mode: mode, etag: etag) {
            case .notModified where hasPicture:
                try? manager.setAttributes([.modificationDate: now()], ofItemAtPath: names.picture.path)
                return names.picture
            case .notModified, .text:
                // A 304 for a picture this phone lost, or a server that reads a dashboard as a plain note.
                return nil
            case .image(let data, let newETag):
                try manager.createDirectory(at: files.cacheDirectory, withIntermediateDirectories: true)
                try data.write(to: names.picture, options: .atomic)
                if let newETag, !newETag.isEmpty {
                    try? Data(newETag.utf8).write(to: names.etag, options: .atomic)
                } else {
                    try? manager.removeItem(at: names.etag)
                }
                trimCache()
                return names.picture
            }
        } catch NotesError.noPreview, NotesError.unreadable {
            return nil
        }
    }
    
    func chart(roomID: String, path: String, mode: NoteDrawingMode) async throws -> NotesChart {
        try await api.chart(roomID: roomID, path: path, mode: mode)
    }
    
    func dashboard(roomID: String, path: String) async throws -> String {
        try await api.dashboard(roomID: roomID, path: path)
    }
    
    /// Made by the server now, never kept: written to a folder of its own under the temporary directory, named as the
    /// server names it, for the share sheet.
    func export(roomID: String, path: String, format: NoteExportFormat) async throws -> URL {
        let export = try await api.export(roomID: roomID, path: path, format: format, size: format == .png ? 1024 : nil)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("artise-exports").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = export.fileName.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent(name.isEmpty ? "export." + format.rawValue : name)
        try export.data.write(to: url, options: .atomic)
        return url
    }
    
    func recordTypes(roomID: String) async throws -> [NotesRecordType] {
        try await api.recordTypes(roomID: roomID)
    }
    
    func chartPreview(roomID: String, content: String, size: Int, mode: NoteDrawingMode) async throws -> Data {
        try await api.chartPreview(roomID: roomID, content: content, size: size, mode: mode)
    }
    
    /// Where a drawing and its ETag live, next to the other previews: one per path, size and mode, whatever the version.
    struct DrawingNames {
        let directory: URL
        let roomID: String
        let path: String
        let size: Int
        let mode: NoteDrawingMode
        
        private var base: String {
            "drawing-" + NotesSyncEngine.stableHash(roomID + "/" + path) + "-" + String(size) + "-" + mode.rawValue
        }
        
        var picture: URL {
            directory.appendingPathComponent(base + ".png")
        }
        
        var etag: URL {
            directory.appendingPathComponent(base + ".etag")
        }
    }
}
