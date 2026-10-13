//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An unfinished `[[` link at the cursor: what's typed after `[[`, and where that starts (UTF-16).
public struct OpenWikiLink: Equatable, Sendable {
    /// The offset of the first character after `[[`.
    public let start: Int
    public let query: String
}

/// A note offered while typing `[[`: its name, and the text inserted for it.
public struct WikiLinkSuggestion: Equatable, Sendable, Identifiable {
    public let name: String
    public let path: String
    /// The link target: the bare name when it's unique, else the path without `.md`, as Obsidian writes it.
    public let linkText: String
    
    public var id: String {
        path
    }
}

/// Finds an unfinished `[[link` at the cursor and the notes that fit it, as the Android app does.
public enum WikiLinkSuggestions {
    public static let maxSuggestions = 6
    
    /// The `[[…` being typed at `cursor`, or `nil` if the cursor isn't inside one on this line.
    public static func openLink(in text: String, cursor: Int) -> OpenWikiLink? {
        guard cursor >= 2, cursor <= text.utf16Length else { return nil }
        let lineStart = text.lineStart(containing: cursor)
        let before = text.utf16Slice(lineStart, cursor)
        guard let open = before.range(of: "[[", options: .backwards) else { return nil }
        let query = String(before[open.upperBound...])
        // Closed already, or a new link started inside: not an open link.
        // "|" starts the shown text and "#" a heading: suggestions are only for the note's name.
        guard !query.contains("]]"), !query.contains("[["), !query.contains("|"), !query.contains("#") else { return nil }
        let start = lineStart + before.utf16Length - query.utf16Length
        return OpenWikiLink(start: start, query: query)
    }
    
    /// Notes matching `query`, names starting with it first, leaving out `currentPath`.
    public static func suggestions(for query: String, notePaths: [String], currentPath: String?) -> [WikiLinkSuggestion] {
        let wanted = NoteLinkResolver.matchKey(query).trimmingCharacters(in: .whitespaces)
        let nameCounts = Dictionary(grouping: notePaths) { NoteLinkResolver.matchKey(name(of: $0)) }.mapValues(\.count)
        return notePaths
            .filter { $0 != currentPath && $0.hasSuffix(".md") }
            .map { (path: $0, name: name(of: $0)) }
            .filter { wanted.isEmpty || NoteLinkResolver.matchKey($0.name).contains(wanted) || NoteLinkResolver.matchKey($0.path).contains(wanted) }
            .sorted { lhs, rhs in
                let lhsStarts = NoteLinkResolver.matchKey(lhs.name).hasPrefix(wanted)
                let rhsStarts = NoteLinkResolver.matchKey(rhs.name).hasPrefix(wanted)
                if lhsStarts != rhsStarts {
                    return lhsStarts
                }
                if lhs.name.lowercased() != rhs.name.lowercased() {
                    return lhs.name.lowercased() < rhs.name.lowercased()
                }
                return lhs.path < rhs.path
            }
            .prefix(maxSuggestions)
            .map { candidate in
                let isUnique = (nameCounts[NoteLinkResolver.matchKey(candidate.name)] ?? 0) <= 1
                return WikiLinkSuggestion(name: candidate.name, path: candidate.path,
                                          linkText: isUnique ? candidate.name : String(candidate.path.dropLast(3)))
            }
    }
    
    /// The text with the open link completed as `[[linkText]]`, and the cursor after it.
    public static func complete(_ text: String, link: OpenWikiLink, cursor: Int, with suggestion: WikiLinkSuggestion) -> EditedText {
        // A "]]" already typed after the cursor is swallowed.
        let end = text.hasPrefix("]]", atUTF16: cursor) ? cursor + 2 : cursor
        let inserted = suggestion.linkText + "]]"
        let after = link.start + inserted.utf16Length
        return EditedText(text: text.replacingUTF16(link.start, end, with: inserted), start: after, end: after)
    }
    
    private static func name(of path: String) -> String {
        let file = NotesFolderEntries.fileName(path)
        return file.hasSuffix(".md") ? String(file.dropLast(3)) : file
    }
}
