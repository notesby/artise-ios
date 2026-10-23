//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// A CSV from the notes as its text, in a fixed-width font, scrolling both ways. Find works on the phone: every match
/// marked in place, the current one scrolled to. "Open with" hands the whole file to another app.
struct NoteTableScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    
    @State private var file: URL?
    @State private var table: TableText?
    @State private var failed = false
    @State private var isSearching = false
    @State private var query = ""
    @State private var find = NoteTableFind()
    
    var body: some View {
        VStack(spacing: 0) {
            if isSearching, table != nil {
                NoteSearchBar(query: $query, status: find.status, onNext: { find.next() }, onPrevious: { find.previous() }) {
                    isSearching = false
                    query = ""
                }
            }
            if let table {
                lines(table)
            } else if failed {
                Text(ArtiseNotesL10n.text("screen_notes_attachment_unavailable"))
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.compound.bgCanvasDefault)
        .navigationTitle(NotesFolderEntries.fileName(path))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let file {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: file) {
                        CompoundIcon(\.shareIos)
                    }
                    .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_open_with"))
                }
            }
            if table != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { isSearching.toggle() } label: {
                        CompoundIcon(\.search)
                    }
                    .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_find"))
                }
            }
        }
        .onChange(of: query) { _, query in
            if let table {
                find.search(query, in: table)
            }
        }
        .task { await load() }
    }
    
    private func lines(_ table: TableText) -> some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(table.lines.indices, id: \.self) { index in
                        Text(NoteFindHighlight.apply(to: AttributedString(table.lines[index]),
                                                     ranges: find.ranges(onLine: index),
                                                     current: find.current?.line == index ? find.current?.range : nil))
                            .font(.compound.bodyMD.monospaced())
                            .foregroundStyle(.compound.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .id(index)
                    }
                    if table.isCut {
                        Text(ArtiseNotesL10n.text("screen_notes_table_cut"))
                            .font(.compound.bodySM)
                            .foregroundStyle(.compound.textSecondary)
                            .padding(.top, 12)
                    }
                }
                .padding(16)
            }
            .onChange(of: find.current) { _, current in
                guard let current else { return }
                // Across to the match's place in its line, as well as down to the line.
                let length = max(1, (table.lines[current.line] as NSString).length)
                withAnimation { proxy.scrollTo(current.line, anchor: UnitPoint(x: Double(current.range.lowerBound) / Double(length), y: 0.5)) }
            }
        }
    }
    
    private func load() async {
        let repository = service.repository
        guard let url = try? await repository.attachment(roomID: roomID, path: path) else {
            failed = true
            return
        }
        file = url
        table = await Task.detached { (try? Data(contentsOf: url)).map { TableText(data: $0) } }.value
        failed = table == nil
    }
}

/// Find in a table's text, on the phone: no server call.
struct NoteTableFind {
    private(set) var matches: [TableMatch] = []
    private(set) var cursor = SearchCursor(count: 0)
    private(set) var status = NoteSearchStatus.idle
    private var byLine: [Int: [Range<Int>]] = [:]
    
    var current: TableMatch? {
        cursor.index.map { matches[$0] }
    }
    
    func ranges(onLine line: Int) -> [Range<Int>] {
        byLine[line] ?? []
    }
    
    mutating func search(_ query: String, in table: TableText) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        matches = needle.isEmpty ? [] : table.matches(for: needle)
        byLine = Dictionary(grouping: matches, by: \.line).mapValues { $0.map(\.range) }
        cursor = SearchCursor(count: matches.count)
        updateStatus(isEmpty: needle.isEmpty)
    }
    
    mutating func next() {
        cursor.next()
        updateStatus(isEmpty: false)
    }
    
    mutating func previous() {
        cursor.previous()
        updateStatus(isEmpty: false)
    }
    
    private mutating func updateStatus(isEmpty: Bool) {
        if let position = cursor.position {
            status = .found(position: position, total: cursor.count)
        } else {
            status = isEmpty ? .idle : .none
        }
    }
}

/// Marks what a search found in a run of text: every match light yellow, the current one strong amber. The same
/// colours as Android and as everywhere find shows (reading view, editor, PDF, CSV), readable in both themes.
enum NoteFindHighlight {
    static let match = UIColor(red: 1, green: 0xD5 / 255, blue: 0x4F / 255, alpha: 0.4)
    static let current = UIColor(red: 1, green: 0xB3 / 255, blue: 0, alpha: 0.8)
    
    static func apply(to text: AttributedString, ranges: [Range<Int>], current: Range<Int>?) -> AttributedString {
        guard !ranges.isEmpty else { return text }
        var result = text
        for range in ranges {
            guard let marked = Range(NSRange(location: range.lowerBound, length: range.count), in: result) else { continue }
            result[marked].backgroundColor = Color(range == current ? Self.current : Self.match)
        }
        return result
    }
}

/// An Office file the server has no PDF of: its icon, and a hint to use "Open with". Not an error.
struct NoteOfficeHint: View {
    let kind: NoteDocumentKind
    
    var body: some View {
        VStack(spacing: 16) {
            CompoundIcon(ArtiseNoteDocument.icon(kind), size: .custom(48), relativeTo: .compound.headingLGBold)
                .foregroundStyle(.compound.iconSecondary)
            Text(ArtiseNotesL10n.text("screen_notes_office_hint"))
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
