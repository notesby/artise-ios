//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Why a name typed for a new note can't be used.
public enum NoteNameProblem: Equatable, Sendable {
    /// Empty, has a "/" (which would make a folder), or starts with "." (hidden on the server).
    case invalid
    /// A note with that name is already in the folder.
    case exists
}

/// Turns what people type ("Súper", "Lista de la compra") into note paths, and checks them, as the Android app does.
public enum NoteNames {
    /// The path for `name` in `folder`: "Recetas" + "Mole" → "Recetas/Mole.md".
    public static func path(for name: String, in folder: String) -> String {
        var file = name.trimmingCharacters(in: .whitespaces)
        if file.hasSuffix(".md") {
            file.removeLast(3)
        }
        file += ".md"
        return folder.isEmpty ? file : folder + "/" + file
    }
    
    /// `path`, or "Ideas (2).md", "Ideas (3).md"… when it's taken (ignoring case), to keep both notes.
    public static func freePath(for path: String, taken: [String]) -> String {
        let used = Set(taken.map { $0.lowercased() })
        guard used.contains(path.lowercased()) else { return path }
        let base = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
        let suffix = path.hasSuffix(".md") ? ".md" : ""
        var number = 2
        while used.contains("\(base) (\(number))\(suffix)".lowercased()) {
            number += 1
        }
        return "\(base) (\(number))\(suffix)"
    }
    
    /// The problem with `name` in `folder`, or `nil` if it can be used. `existingPaths` are the chat's files.
    public static func problem(with name: String, in folder: String, existingPaths: [String]) -> NoteNameProblem? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.contains("/") || trimmed.hasPrefix(".") {
            return .invalid
        }
        let path = path(for: trimmed, in: folder)
        if existingPaths.contains(where: { $0.caseInsensitiveCompare(path) == .orderedSame }) {
            return .exists
        }
        return nil
    }
    
    /// `path` renamed to `newName` in the same folder. A note named "Mole" stays "Mole.md"; a file keeps its extension
    /// when the new name leaves it out ("factura.pdf" renamed "recibo" → "recibo.pdf").
    public static func renamedPath(_ path: String, to newName: String) -> String {
        let folder = NotesFolderEntries.parentFolder(of: path)
        let name = newName.trimmingCharacters(in: .whitespaces)
        let fileName = NotesFolderEntries.fileName(path)
        let ext = fileName.contains(".") ? String(fileName.split(separator: ".").last ?? "") : ""
        let file = if ext.isEmpty || name.lowercased().hasSuffix("." + ext.lowercased()) {
            name
        } else {
            name + "." + ext
        }
        return folder.isEmpty ? file : folder + "/" + file
    }
    
    /// The problem with renaming `path` to `newName`, or `nil`; `existingPaths` are the chat's files and folders.
    public static func renameProblem(_ path: String, to newName: String, existingPaths: [String]) -> NoteNameProblem? {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.contains("/") || trimmed.hasPrefix(".") {
            return .invalid
        }
        let target = renamedPath(path, to: trimmed)
        let isTaken = target.caseInsensitiveCompare(path) != .orderedSame
            && existingPaths.contains { $0.caseInsensitiveCompare(target) == .orderedSame }
        return isTaken ? .exists : nil
    }
    
    /// `path` moved into `folder` ("" for the top level), keeping its name.
    public static func movedPath(_ path: String, to folder: String) -> String {
        let name = NotesFolderEntries.fileName(path)
        return folder.isEmpty ? name : folder + "/" + name
    }
    
    /// The folder `path` renamed to `newName` in the same parent.
    public static func renamedFolder(_ path: String, to newName: String) -> String {
        movedPath(newName.trimmingCharacters(in: .whitespaces), to: NotesFolderEntries.parentFolder(of: path))
    }
    
    /// "  Recetas / Postres/ " → "Recetas/Postres".
    public static func folderPath(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "/")
    }
    
    /// The problem with a folder called `name` ("Postres", or "Recetas/Postres" for one inside another), or `nil`.
    public static func folderProblem(_ name: String) -> NoteNameProblem? {
        let parts = folderPath(name).split(separator: "/", omittingEmptySubsequences: false)
        return parts.contains { $0.isEmpty || $0.hasPrefix(".") } ? .invalid : nil
    }
}
