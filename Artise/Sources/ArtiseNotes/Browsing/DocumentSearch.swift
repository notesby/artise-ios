//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// One place a search found its words: the page (1 for a note, a PDF's page number) and the range in that page's
/// text, in UTF-16 offsets as text views count them.
public struct DocumentMatch: Equatable, Sendable {
    public let page: Int
    public let range: Range<Int>
    
    public init(page: Int, range: Range<Int>) {
        self.page = page
        self.range = range
    }
}

/// Finds words in a document's text the way people type them: "camion" finds "camión", "MOLE" finds "mole".
public enum DocumentSearch {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    
    /// Every match in one text, in order; none for an empty query.
    public static func ranges(of query: String, in text: String) -> [Range<Int>] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let haystack = text as NSString
        var found: [Range<Int>] = []
        var from = 0
        while from < haystack.length {
            let hit = haystack.range(of: needle, options: options, range: NSRange(location: from, length: haystack.length - from))
            guard hit.location != NSNotFound, hit.length > 0 else { break }
            found.append(hit.location..<NSMaxRange(hit))
            from = NSMaxRange(hit)
        }
        return found
    }
    
    /// Every match across a document's pages, page by page, in order.
    public static func matches(for query: String, in pages: [NotesDocumentText.Page]) -> [DocumentMatch] {
        pages.sorted { $0.number < $1.number }.flatMap { page in
            ranges(of: query, in: page.text).map { DocumentMatch(page: page.number, range: $0) }
        }
    }
    
    /// A few words around a match, for a page the viewer can't highlight on.
    public static func snippet(around range: Range<Int>, in text: String, context: Int = 30) -> String {
        let whole = text as NSString
        let start = max(0, range.lowerBound - context)
        let end = min(whole.length, range.upperBound + context)
        var piece = whole.substring(with: NSRange(location: start, length: end - start))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if start > 0 {
            piece = "…" + piece
        }
        if end < whole.length {
            piece += "…"
        }
        return piece
    }
}

/// Which match is current, with next and previous that wrap around.
public struct SearchCursor: Equatable, Sendable {
    public let count: Int
    /// From 0; `nil` when there's nothing to point at.
    public private(set) var index: Int?
    
    public init(count: Int) {
        self.count = count
        index = count > 0 ? 0 : nil
    }
    
    /// The number people see: "3 of 12".
    public var position: Int? {
        index.map { $0 + 1 }
    }
    
    public mutating func next() {
        guard let index, count > 0 else { return }
        self.index = (index + 1) % count
    }
    
    public mutating func previous() {
        guard let index, count > 0 else { return }
        self.index = (index + count - 1) % count
    }
}
