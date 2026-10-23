//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// One run of text as the reading view draws it, with where it sits: the top-level block's index, then the piece,
/// list item, nested block or table row inside it. The reading view gives each drawn text the same `slot`, so a
/// match found here is highlighted and scrolled to there.
public struct NoteTextSlot: Equatable, Sendable {
    public let slot: [Int]
    public let text: String
}

/// A match in a note's reading view: the run it's in, which match of that run it is, and its UTF-16 range.
public struct NoteReadingMatch: Equatable, Sendable {
    public let slot: [Int]
    public let occurrence: Int
    public let range: Range<Int>
}

/// Find in a note as it reads: over the rendered words (headings, paragraphs, list items, table rows, code), top to
/// bottom, never over the Markdown marks.
public enum NoteReadingFind {
    /// The separator between a table row's cells, as the reading view draws them.
    public static let cellSeparator = "  ·  "
    
    public static func slots(in blocks: [NoteBlock], prefix: [Int] = []) -> [NoteTextSlot] {
        blocks.enumerated().flatMap { index, block in
            slots(in: block, at: prefix + [index])
        }
    }
    
    public static func matches(for query: String, in blocks: [NoteBlock]) -> [NoteReadingMatch] {
        slots(in: blocks).flatMap { slot in
            DocumentSearch.ranges(of: query, in: slot.text).enumerated().map { occurrence, range in
                NoteReadingMatch(slot: slot.slot, occurrence: occurrence, range: range)
            }
        }
    }
    
    /// A table row as one line: "cell  ·  cell  ·  cell".
    public static func row(_ cells: [[NoteInline]]) -> [NoteInline] {
        var inlines: [NoteInline] = []
        for (index, cell) in cells.enumerated() {
            if index > 0 {
                inlines.append(.text(cellSeparator))
            }
            inlines += cell
        }
        return inlines
    }
    
    private static func slots(in block: NoteBlock, at path: [Int]) -> [NoteTextSlot] {
        switch block {
        case .heading(_, let text):
            return [NoteTextSlot(slot: path, text: text.plainText)]
        case .paragraph(let pieces):
            return pieces.enumerated().compactMap { index, piece in
                guard case .text(let inlines) = piece else { return nil }
                return NoteTextSlot(slot: path + [index], text: inlines.plainText)
            }
        case .list(_, _, let items):
            return items.enumerated().flatMap { index, item in
                slots(in: item.blocks, prefix: path + [index])
            }
        case .quote(let blocks):
            return slots(in: blocks, prefix: path)
        case .code(let code):
            return [NoteTextSlot(slot: path, text: code)]
        case .table(let rows):
            return rows.enumerated().map { index, cells in
                NoteTextSlot(slot: path + [index], text: row(cells).plainText)
            }
        case .divider:
            return []
        case .html(let html):
            return [NoteTextSlot(slot: path, text: html)]
        }
    }
}

/// A CSV (or other text file) as the table viewer shows it: its lines, cut at about half a million characters so a
/// huge file can't stall the phone. "Open with" still hands over the whole file.
public struct TableText: Equatable, Sendable {
    public static let characterLimit = 500_000
    
    public let lines: [String]
    public let isCut: Bool
    
    public init(data: Data, limit: Int = characterLimit) {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        isCut = text.count > limit
        if isCut {
            text = String(text.prefix(limit))
        }
        lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
    
    /// Every match, line by line, in order.
    public func matches(for query: String) -> [TableMatch] {
        lines.enumerated().flatMap { line, text in
            DocumentSearch.ranges(of: query, in: text).enumerated().map { occurrence, range in
                TableMatch(line: line, occurrence: occurrence, range: range)
            }
        }
    }
}

public struct TableMatch: Equatable, Sendable {
    public let line: Int
    public let occurrence: Int
    public let range: Range<Int>
}
