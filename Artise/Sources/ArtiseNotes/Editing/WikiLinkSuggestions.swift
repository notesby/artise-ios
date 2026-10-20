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

/// A note, page or file offered while typing `[[`: the name that matched, and the text inserted for it.
public struct WikiLinkSuggestion: Equatable, Sendable, Identifiable {
    /// The note's name, the page's title, or the alias that matched.
    public let name: String
    public let path: String
    /// The link target as Obsidian writes it: the bare name when it's unique, `Ana|Mamá` for an alias,
    /// `people/Ana|Ana` when another note shares the name.
    public let linkText: String
    /// What tells it apart: the page's own name for an alias, the folder and summary for a shared name.
    public let detail: String?
    
    public init(name: String, path: String, linkText: String, detail: String? = nil) {
        self.name = name
        self.path = path
        self.linkText = linkText
        self.detail = detail
    }
    
    public var id: String {
        linkText
    }
}

/// Finds an unfinished `[[link` at the cursor and the notes, pages and files that fit it, as the Android app does.
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
    
    /// Notes matching `query` by name, names starting with it first, leaving out `currentPath`.
    public static func suggestions(for query: String, notePaths: [String], currentPath: String?) -> [WikiLinkSuggestion] {
        suggestions(for: query, index: PageIndex(paths: notePaths, pages: []), currentPath: currentPath)
    }
    
    /// Notes, pages and files matching `query` by name, title or alias: names starting with it first, then notes
    /// before photos and documents. The note being edited is left out.
    public static func suggestions(for query: String, index: PageIndex, currentPath: String?) -> [WikiLinkSuggestion] {
        let wanted = NoteLinkResolver.matchKey(query).trimmingCharacters(in: .whitespaces)
        return entries(index)
            .filter { $0.path != currentPath }
            .filter { wanted.isEmpty || NoteLinkResolver.matchKey($0.name).contains(wanted) || ($0.matchesPath && NoteLinkResolver.matchKey($0.path).contains(wanted)) }
            .sorted { lhs, rhs in
                let lhsStarts = NoteLinkResolver.matchKey(lhs.name).hasPrefix(wanted)
                let rhsStarts = NoteLinkResolver.matchKey(rhs.name).hasPrefix(wanted)
                if lhsStarts != rhsStarts {
                    return lhsStarts
                }
                if lhs.isNote != rhs.isNote {
                    return lhs.isNote
                }
                if lhs.name.lowercased() != rhs.name.lowercased() {
                    return lhs.name.lowercased() < rhs.name.lowercased()
                }
                return lhs.path < rhs.path
            }
            .prefix(maxSuggestions)
            .map(\.suggestion)
    }
    
    /// The text with the open link completed as `[[linkText]]`, and the cursor after it.
    public static func complete(_ text: String, link: OpenWikiLink, cursor: Int, with suggestion: WikiLinkSuggestion) -> EditedText {
        // A "]]" already typed after the cursor is swallowed.
        let end = text.hasPrefix("]]", atUTF16: cursor) ? cursor + 2 : cursor
        let inserted = suggestion.linkText + "]]"
        let after = link.start + inserted.utf16Length
        return EditedText(text: text.replacingUTF16(link.start, end, with: inserted), start: after, end: after)
    }
    
    private struct Entry {
        let name: String
        let path: String
        let isNote: Bool
        /// Typing part of the folder finds a note by its name entry, not by its aliases.
        let matchesPath: Bool
        let suggestion: WikiLinkSuggestion
    }
    
    /// One entry per note (by its name), plus one per page alias and one per photo or document with a page.
    private static func entries(_ index: PageIndex) -> [Entry] {
        let notes = index.paths.filter { $0.hasSuffix(".md") }
        let files = index.pages.filter { !$0.isNote }.map(\.path)
        let all = notes + files
        let counts = index.counts(ofNames: all)
        var entries: [Entry] = []
        for path in all {
            let title = index.title(of: path)
            let shared = counts[NoteLinkResolver.matchKey(title), default: 0] > 1
            let page = index.page(at: path)
            let detail = shared ? sharedDetail(path: path, summary: page?.summary ?? "") : nil
            let linkText = shared ? PageIndex.pathForm(path) + (path.hasSuffix(".md") ? "|" + title : "") : title
            entries.append(Entry(name: title, path: path, isNote: path.hasSuffix(".md"), matchesPath: true,
                                 suggestion: WikiLinkSuggestion(name: title, path: path, linkText: linkText, detail: detail)))
            for alias in page?.aliases ?? [] where !alias.isEmpty {
                let target = shared ? PageIndex.pathForm(path) : title
                entries.append(Entry(name: alias, path: path, isNote: path.hasSuffix(".md"), matchesPath: false,
                                     suggestion: WikiLinkSuggestion(name: alias, path: path, linkText: target + "|" + alias, detail: title)))
            }
        }
        return entries
    }
    
    /// "people · Ana, Hector's mother", or the folder alone; "/" for the top level.
    private static func sharedDetail(path: String, summary: String) -> String {
        let folder = NotesFolderEntries.parentFolder(of: path)
        let place = folder.isEmpty ? "/" : folder
        return summary.isEmpty ? place : place + " · " + summary
    }
}
