//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The header Obsidian keeps at the top of a page, between two `---` lines: its `type`, `aliases` and `summary`.
/// Shown as fields, never as text, so `---` doesn't turn the first line into a heading.
public struct NoteFrontmatter: Equatable, Sendable {
    public let type: String?
    public let aliases: [String]
    public let summary: String?
    
    public init(type: String?, aliases: [String], summary: String?) {
        self.type = type
        self.aliases = aliases
        self.summary = summary
    }
    
    /// Anything worth showing above the note.
    public var hasFields: Bool {
        type != nil || !aliases.isEmpty
    }
    
    /// The header and the note's text without it; the text as is when there's no header.
    public static func split(_ markdown: String) -> (header: NoteFrontmatter?, body: String) {
        var lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---", lines.count > 1,
              let close = lines[1...].firstIndex(where: { ["---", "..."].contains($0.trimmingCharacters(in: .whitespaces)) }) else {
            return (nil, markdown)
        }
        let header = parse(Array(lines[1..<close]))
        lines.removeSubrange(0...close)
        return (header, lines.joined(separator: "\n"))
    }
    
    private static func parse(_ lines: [String]) -> NoteFrontmatter {
        var fields: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var openList: String?
        for line in lines {
            if let openList, let item = line.trimmingCharacters(in: .whitespaces).dropFirstPrefix("- ") {
                lists[openList, default: []].append(unquoted(item))
                continue
            }
            openList = nil
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                openList = key
            } else if value.hasPrefix("["), value.hasSuffix("]") {
                lists[key] = value.dropFirst().dropLast().split(separator: ",").map { unquoted($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
            } else {
                fields[key] = unquoted(value)
            }
        }
        let aliases = lists["aliases"] ?? fields["aliases"].map { [$0] } ?? []
        return NoteFrontmatter(type: fields["type"].flatMap { $0.isEmpty ? nil : $0 }, aliases: aliases.filter { !$0.isEmpty },
                               summary: fields["summary"].flatMap { $0.isEmpty ? nil : $0 })
    }
    
    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last, first == last, "\"'".contains(first) else { return value }
        return String(value.dropFirst().dropLast())
    }
}

private extension String {
    func dropFirstPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
