//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Searches the chat's notes on the phone, so it works offline. Every word must appear, ignoring case and accents;
/// notes whose name matches come first. The same rules as the Android app's `LocalNotesSearch`.
public enum LocalNotesSearch {
    public static let maxResults = 50
    public static let maxLines = 3
    
    public static func search(_ files: [LocalFile], query: String) -> [NotesSearchResult] {
        let words = normalized(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        let hits: [(path: String, nameMatches: Bool, lines: [String])] = files.filter(\.isNote).compactMap { file in
            let name = normalized(file.path)
            let nameMatches = words.allSatisfy { name.contains($0) }
            let lines = (file.content ?? "").split(separator: "\n", omittingEmptySubsequences: true).filter { line in
                let text = normalized(String(line))
                return !text.trimmingCharacters(in: .whitespaces).isEmpty && words.allSatisfy { text.contains($0) }
            }
            guard nameMatches || !lines.isEmpty else { return nil }
            return (file.path, nameMatches, lines.prefix(maxLines).map { $0.trimmingCharacters(in: .whitespaces) })
        }
        return hits
            .sorted { lhs, rhs in
                lhs.nameMatches != rhs.nameMatches ? lhs.nameMatches : lhs.path.lowercased() < rhs.path.lowercased()
            }
            .prefix(maxResults)
            .map { NotesSearchResult(path: $0.path, lines: $0.lines) }
    }
    
    static func normalized(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }
}
