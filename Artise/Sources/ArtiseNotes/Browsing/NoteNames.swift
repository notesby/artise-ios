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
}
