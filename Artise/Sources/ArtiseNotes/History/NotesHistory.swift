//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// What a change did to one file.
public enum FileChange: String, Equatable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
    
    /// A kind a newer server adds reads as a plain modification.
    init(serverValue: String) {
        self = FileChange(rawValue: serverValue) ?? .modified
    }
}

public struct ChangedFile: Equatable, Sendable {
    public let path: String
    public let change: FileChange
    /// The old path, for a rename or copy.
    public let from: String?
}

/// One change to a chat's notes, as `GET /changes` lists it.
public struct NotesChange: Equatable, Sendable {
    public let commit: String
    /// ISO 8601 with the server's offset.
    public let at: String
    public let message: String
    public let author: ChangeAuthor
    public let files: [ChangedFile]
}

public struct NotesChangesPage: Equatable, Sendable {
    public let changes: [NotesChange]
    /// Older changes exist: ask again with the last commit as `before`.
    public let more: Bool
}

/// Who a change was for and how it was made, ready to put in words, as in the Android app:
/// "Ari, asked by Ana", "Ana, in the app", "A synced device"…
public enum ChangeLabel: Equatable, Sendable {
    /// A text from the `ArtiseNotes` table with its arguments.
    case text(key: String, arguments: [String])
    /// The server's plain name, for authors this app doesn't know how to describe.
    case plain(String)
    
    public init(_ author: ChangeAuthor) {
        let who = author.who?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let detail = author.detail.trimmingCharacters(in: .whitespaces)
        let fallback = ChangeLabel.plain(author.by)
        // Labels that name a person fall back to the plain name when the server didn't say who.
        func forWho(_ key: String, _ extra: String...) -> ChangeLabel {
            who.map { .text(key: key, arguments: [$0] + extra) } ?? fallback
        }
        self = switch author.how {
        case "ari": forWho("screen_notes_change_ari")
        case "automation": forWho("screen_notes_change_automation", detail)
        case "routine": forWho("screen_notes_change_routine", detail)
        case "brief": forWho("screen_notes_change_brief", detail)
        case "ari_own": .text(key: "screen_notes_change_ari_own", arguments: [])
        case "reaction": forWho("screen_notes_change_reaction")
        case "chat": forWho("screen_notes_change_chat")
        case "app": forWho("screen_notes_change_app")
        case "files": forWho("screen_notes_change_files")
        case "sync": .text(key: "screen_notes_change_sync", arguments: [])
        default: fallback
        }
    }
    
    /// Without a detail ("#3"), "Ari, Ana's automation " would keep a stray space: tidied.
    public static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
}

/// Changes grouped by the day they were made, newest first, for the history screens.
public enum HistoryDays {
    /// The date of an ISO 8601 time from the server, or `nil` when it can't be read.
    public static func date(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }
    
    /// Items in order, cut where the day (in the phone's time zone) changes.
    public static func grouped<Item>(_ items: [Item], at time: (Item) -> String, calendar: Calendar = .current) -> [(day: Date?, items: [Item])] {
        var groups: [(day: Date?, items: [Item])] = []
        for item in items {
            let day = date(time(item)).map { calendar.startOfDay(for: $0) }
            if let last = groups.last, last.day == day {
                groups[groups.count - 1].items.append(item)
            } else {
                groups.append((day, [item]))
            }
        }
        return groups
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
