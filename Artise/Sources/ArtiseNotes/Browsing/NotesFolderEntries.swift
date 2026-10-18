//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// One row in a folder of notes.
public enum NotesFolderEntry: Equatable, Sendable, Identifiable {
    case folder(name: String, path: String, notes: Int, files: Int)
    case note(name: String, path: String, hasLocalEdits: Bool)
    case file(name: String, path: String, isImage: Bool, size: Int64)
    
    public var id: String {
        switch self {
        case .folder(_, let path, _, _): "folder:" + path
        case .note(_, let path, _): "note:" + path
        case .file(_, let path, _, _): "file:" + path
        }
    }
}

/// What a folder shows, as in the Android app: its subfolders (with how many notes and files they hold),
/// then its notes and files, each sorted by name.
public enum NotesFolderEntries {
    static let imageExtensions: Set = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp"]
    
    /// - Parameters:
    ///   - folder: "" for the top level, "Recetas/Postres" for a subfolder.
    ///   - allFolders: every folder in the chat, so empty ones show too.
    public static func entries(files: [LocalFile], folder: String, allFolders: [String] = []) -> [NotesFolderEntry] {
        let prefix = folder.isEmpty ? "" : folder + "/"
        let inFolder = files.filter { $0.path.hasPrefix(prefix) }
        let deeper = Dictionary(grouping: inFolder.filter { $0.path.dropFirst(prefix.count).contains("/") }) { file in
            String(file.path.dropFirst(prefix.count).prefix { $0 != "/" })
        }
        // Folders without any file inside (empty, or holding only empty folders) show too.
        let emptyFolders = allFolders
            .filter { $0.hasPrefix(prefix) && $0.count > prefix.count }
            .map { String($0.dropFirst(prefix.count).prefix { $0 != "/" }) }
        let folders = Set(deeper.keys).union(emptyFolders).map { name -> NotesFolderEntry in
            let inside = deeper[name] ?? []
            return .folder(name: name, path: prefix + name, notes: inside.filter(\.isNote).count, files: inside.filter { !$0.isNote }.count)
        }
        
        let here = inFolder.filter { !$0.path.dropFirst(prefix.count).contains("/") }
        let notes = here.filter(\.isNote).map { NotesFolderEntry.note(name: noteName($0.path), path: $0.path, hasLocalEdits: $0.hasLocalEdits) }
        let others = here.filter { !$0.isNote }.map { file in
            NotesFolderEntry.file(name: fileName(file.path), path: file.path, isImage: isImage(file.path), size: file.size)
        }
        return sortedByName(folders) + sortedByName(notes) + sortedByName(others)
    }
    
    /// "Recetas/Mole.md" → "Mole"; other text files keep their extension, so "lista.csv" stays recognisable.
    public static func noteName(_ path: String) -> String {
        let name = fileName(path)
        return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }
    
    /// "Recetas/Postres/Flan.md" → "Recetas/Postres"; "" at the top level.
    public static func parentFolder(of path: String) -> String {
        guard let slash = path.range(of: "/", options: .backwards) else { return "" }
        return String(path[..<slash.lowerBound])
    }
    
    public static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
    
    public static func isImage(_ path: String) -> Bool {
        imageExtensions.contains((path.split(separator: ".").last.map(String.init) ?? "").lowercased())
    }
    
    private static func sortedByName(_ entries: [NotesFolderEntry]) -> [NotesFolderEntry] {
        entries.sorted { name(of: $0).localizedCaseInsensitiveCompare(name(of: $1)) == .orderedAscending }
    }
    
    private static func name(of entry: NotesFolderEntry) -> String {
        switch entry {
        case .folder(let name, _, _, _), .note(let name, _, _), .file(let name, _, _, _): name
        }
    }
}
