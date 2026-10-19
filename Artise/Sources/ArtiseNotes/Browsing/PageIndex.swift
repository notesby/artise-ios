//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// What a `[[link]]` points to among the chat's files and pages.
public enum LinkResolution: Equatable, Sendable {
    case file(String)
    /// Several notes answer to the name, as the server reports with `candidates`: the person chooses, never the first.
    case ambiguous([LinkCandidate])
    /// Nothing has that name yet.
    case missing
}

/// One of the notes sharing a link's name, with what tells them apart.
public struct LinkCandidate: Equatable, Sendable, Identifiable {
    public let path: String
    public let title: String
    /// The folder the note is in, "" at the top level.
    public let folder: String
    public let summary: String
    public let type: String
    
    public var id: String {
        path
    }
    
    /// A link to this note and no other, as Obsidian writes it: `people/Ana|Ana`.
    public var linkText: String {
        PageIndex.pathForm(path) + "|" + title
    }
}

/// A link to write for a name typed by hand: the target, and the text shown instead of it.
public struct WrittenLink: Equatable, Sendable {
    public let target: String
    public let shownText: String
}

/// The chat's files and pages together, read the way Obsidian and the Notes API read links: a path first, then a
/// file's name in any folder, then a page's title, then one of its aliases. Case and accents are ignored. When two
/// notes answer to the same name the link is ambiguous, and a link to one of them is written by path.
public struct PageIndex: Equatable, Sendable {
    public let paths: [String]
    public let pages: [NotesPage]
    private let pagesByPath: [String: NotesPage]
    
    public static let empty = PageIndex(paths: [], pages: [])
    
    public init(paths: [String], pages: [NotesPage]) {
        self.paths = paths
        self.pages = pages
        pagesByPath = Dictionary(pages.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    }
    
    public func page(at path: String) -> NotesPage? {
        pagesByPath[path]
    }
    
    /// A note with a page of its own (its folder is in a `(pages)` section of the chat's `SCHEMA.md`).
    public func isPage(_ path: String) -> Bool {
        pagesByPath[path]?.isNote == true
    }
    
    /// The name people call `path` by: the page's title, else the file's name.
    public func title(of path: String) -> String {
        pagesByPath[path]?.title ?? NotesFolderEntries.noteName(path)
    }
    
    public func resolve(_ target: String) -> LinkResolution {
        var wanted = target.trimmingCharacters(in: .whitespaces)
        if wanted.hasPrefix("/") {
            wanted.removeFirst()
        }
        guard !wanted.isEmpty else { return .missing }
        // "luna.jpg" names a file; "Sr. Pérez" is still a note, so only a short trailing extension counts.
        let forms = NoteLinkResolver.hasExtension(wanted) ? [wanted] : [wanted + ".md", wanted]
        // A path form (`people/Ana`) names one note. A bare name is looked up in every folder, the top level included,
        // so `[[Mole]]` with a Mole.md at the top and another in Recetas/ is ambiguous rather than the top one.
        if wanted.contains("/") {
            let byPath = Dictionary(grouping: paths, by: NoteLinkResolver.matchKey)
            for form in forms {
                if let match = byPath[NoteLinkResolver.matchKey(form)]?.min(by: { $0.count < $1.count }) {
                    return .file(match)
                }
            }
        }
        let nameKeys = Set(forms.map { NoteLinkResolver.matchKey(NoteLinkResolver.fileName($0)) })
        let byName = paths.filter { nameKeys.contains(NoteLinkResolver.matchKey(NoteLinkResolver.fileName($0))) }
        if !byName.isEmpty {
            return choose(byName)
        }
        let key = NoteLinkResolver.matchKey(wanted)
        let byTitle = pages.filter { NoteLinkResolver.matchKey($0.title) == key }.map(\.path)
        if !byTitle.isEmpty {
            return choose(byTitle)
        }
        let byAlias = pages.filter { page in page.aliases.contains { NoteLinkResolver.matchKey($0) == key } }.map(\.path)
        return byAlias.isEmpty ? .missing : choose(byAlias)
    }
    
    /// The link to write for a name typed by hand, when it isn't the note's own name: `Mamá` becomes `[[Ana|Mamá]]`.
    /// `nil` keeps what was typed: a path, a note's own name, an unknown name, or an ambiguous one (the tap offers the choice).
    public func written(_ typed: String) -> WrittenLink? {
        let target = typed.trimmingCharacters(in: .whitespaces)
        guard !target.contains("/"), !target.contains("#"), case .file(let path) = resolve(target),
              let page = pagesByPath[path], page.isNote else { return nil }
        let key = NoteLinkResolver.matchKey(target)
        guard NoteLinkResolver.matchKey(page.title) != key, NoteLinkResolver.matchKey(NotesFolderEntries.noteName(path)) != key else { return nil }
        return WrittenLink(target: page.title, shownText: target)
    }
    
    /// The link text that reaches `path` and nothing else: its name when unique, else `folder/Name|Name`.
    public func linkText(for path: String) -> String {
        let title = title(of: path)
        let isUnique = count(ofName: title, among: paths) <= 1
        return isUnique && !path.hasSuffix(".md") ? title : isUnique ? title : Self.pathForm(path) + "|" + title
    }
    
    /// `people/Ana.md` → `people/Ana`; a photo keeps its extension.
    public static func pathForm(_ path: String) -> String {
        path.hasSuffix(".md") ? String(path.dropLast(3)) : path
    }
    
    /// How many files and pages answer to `name`.
    func count(ofName name: String, among candidates: [String]) -> Int {
        let key = NoteLinkResolver.matchKey(name)
        return candidates.filter { NoteLinkResolver.matchKey(title(of: $0)) == key }.count
    }
    
    private func choose(_ matches: [String]) -> LinkResolution {
        if matches.count == 1, let only = matches.first {
            return .file(only)
        }
        return .ambiguous(matches.sorted().map(candidate))
    }
    
    private func candidate(_ path: String) -> LinkCandidate {
        let page = pagesByPath[path]
        return LinkCandidate(path: path, title: page?.title ?? NotesFolderEntries.noteName(path),
                             folder: NotesFolderEntries.parentFolder(of: path), summary: page?.summary ?? "", type: page?.type ?? "")
    }
}
