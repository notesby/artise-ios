//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// What a file in the notes is, by its name: what its card shows and where it opens.
public enum NoteDocumentKind: String, Hashable, Sendable {
    /// `.md` and `.txt`: the reading view, with the editor a tap away.
    case note
    case pdf
    case image
    /// `.csv`: its text in a fixed-width font.
    case table
    /// Word, Excel and PowerPoint files: the server's PDF of them.
    case office
    /// Anything else: its folder, where it can be handed to another app.
    case other
    
    static let noteExtensions: Set = ["md", "txt"]
    static let officeExtensions: Set = ["docx", "doc", "odt", "rtf", "xlsx", "xls", "ods", "pptx", "ppt", "odp"]
    
    public static func of(_ path: String) -> NoteDocumentKind {
        let name = NotesFolderEntries.fileName(path)
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return .other }
        let ext = name[name.index(after: dot)...].lowercased()
        if noteExtensions.contains(ext) {
            return .note
        }
        if ext == "pdf" {
            return .pdf
        }
        if ext == "csv" {
            return .table
        }
        if officeExtensions.contains(ext) {
            return .office
        }
        return NotesFolderEntries.isImage(path) ? .image : .other
    }
}

/// A document Ari made or changed in a turn, as a card under its message.
public struct DocumentCard: Hashable, Sendable {
    public enum Change: String, Hashable, Sendable {
        case created
        case changed
    }
    
    public let path: String
    /// The file's version after that turn, for the preview's cache.
    public let version: String?
    public let kind: NoteDocumentKind
    public let title: String
    public let change: Change?
    public let isDraft: Bool
    
    /// Without a title, the file's name as it is, extension included, as on Android.
    public init(path: String, version: String? = nil, title: String? = nil, change: Change? = nil, isDraft: Bool = false) {
        self.path = path
        self.version = version
        kind = NoteDocumentKind.of(path)
        self.title = title ?? NotesFolderEntries.fileName(path)
        self.change = change
        self.isDraft = isDraft
    }
}

/// Reads `co.artise.documents` from Ari's message (family-wiki's docs/notes-api.md): the documents its turn made or
/// changed. Ari turns its progress message into the reply with an edit, so the latest edit comes first (its
/// `m.new_content`, else its own content); when it lists none, the original's count. Anything odd in the list is
/// left out, never a crash. The same reading as Android's `DocumentCards`.
public enum DocumentCards {
    public static let key = "co.artise.documents"
    public static let maxCards = 4
    
    public static func read(originalJSON: String?, latestEditJSON: String?) -> [DocumentCard] {
        for json in [latestEditJSON, originalJSON] {
            guard let content = content(json) else { continue }
            let list = (content["m.new_content"] as? [String: Any])?[key] ?? content[key]
            let found = list.map(cards) ?? []
            if !found.isEmpty {
                return found
            }
        }
        return []
    }
    
    static func cards(_ value: Any) -> [DocumentCard] {
        guard let entries = value as? [Any] else { return [] }
        var seen = Set<String>()
        var result: [DocumentCard] = []
        for case let entry as [String: Any] in entries {
            let path = ((entry["path"] as? String) ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(["/"]))
            guard !path.isEmpty, seen.insert(path).inserted else { continue }
            let title = (entry["title"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            result.append(DocumentCard(path: path,
                                       version: (entry["version"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                       title: title,
                                       change: (entry["change"] as? String).flatMap(DocumentCard.Change.init(rawValue:)),
                                       isDraft: entry["draft"] as? Bool ?? false))
            if result.count == maxCards {
                break
            }
        }
        return result
    }
    
    private static func content(_ json: String?) -> [String: Any]? {
        guard let json, json.contains(key), let data = json.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return event["content"] as? [String: Any] ?? event
    }
}
