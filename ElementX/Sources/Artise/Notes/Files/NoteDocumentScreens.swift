//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import PDFKit
import QuickLook
import SwiftUI

/// Where a file in the notes opens, by its kind: a note in its reading view, a PDF in the viewer, a CSV as a table,
/// an Office file as the server's PDF of it, a chart or dashboard as the server draws it. Photos and anything else open
/// in Quick Look (`nil`). The kind is the server's when it said (a dashboard is a `.md`), else the name's.
nonisolated enum ArtiseNoteDocument {
    static func route(roomID: String, path: String, kind: NoteDocumentKind? = nil) -> NotesRoute? {
        switch kind ?? NoteDocumentKind.of(path) {
        case .note: .note(roomID: roomID, path: path)
        case .pdf: .pdf(roomID: roomID, path: path)
        case .table: .table(roomID: roomID, path: path)
        case .office: .office(roomID: roomID, path: path)
        case .chart: .chart(roomID: roomID, path: path)
        case .dashboard: .dashboard(roomID: roomID, path: path)
        case .image, .other: nil
        }
    }
    
    /// Files a list shows a small picture of: photos, PDFs and Office files (the server draws their first page), and
    /// charts and dashboards.
    static func hasPicture(_ path: String, kind: NoteDocumentKind? = nil) -> Bool {
        [.image, .pdf, .office, .chart, .dashboard].contains(kind ?? NoteDocumentKind.of(path))
    }
    
    /// The icon for a kind of file, on cards and where a file has no picture (as on Android).
    static func icon(_ kind: NoteDocumentKind) -> KeyPath<CompoundIcons, Image> {
        switch kind {
        case .note: \.document
        case .table: \.grid
        case .image: \.image
        case .chart: \.chart
        case .dashboard: \.polls
        case .pdf, .office, .other: \.attachment
        }
    }
}

/// A document Ari posted or made, opened from the chat: the notes' own copy, updated first so it's the current one.
/// It opens where it would from the notes list; a file the app can't read opens in its folder, where "Open with"
/// hands it to another app.
struct ArtiseNoteDocumentView: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    /// What the card or message said it is, for a file the phone doesn't list yet.
    var kind: NoteDocumentKind?
    let onClose: () -> Void
    
    @State private var stage = Stage.loading
    @State private var previewURL: URL?
    
    private enum Stage: Equatable {
        case loading
        case screen(NotesRoute)
        case folder
        case quickLook
        case unavailable
    }
    
    var body: some View {
        Group {
            switch stage {
            case .screen(.pdf(let roomID, let path)):
                NotePDFSheet(service: service, roomID: roomID, path: path, onClose: onClose)
            case .screen(let route):
                closable { NotesDestination(service: service, route: route) }
            case .folder:
                closable { NotesFolderScreen(service: service, roomID: roomID, folder: NotesFolderEntries.parentFolder(of: path), title: nil) }
            case .loading, .quickLook, .unavailable:
                closable {
                    Group {
                        if stage == .unavailable {
                            Text(ArtiseNotesL10n.text("screen_notes_attachment_unavailable"))
                                .font(.compound.bodyLG)
                                .foregroundStyle(.compound.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(32)
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.compound.bgCanvasDefault)
                    .navigationTitle(NotesFolderEntries.fileName(path))
                    .navigationBarTitleDisplayMode(.inline)
                }
                .quickLookPreview($previewURL)
                .onChange(of: previewURL) { _, url in
                    // Quick Look closed: nothing is left to show.
                    if url == nil, stage == .quickLook {
                        onClose()
                    }
                }
            }
        }
        .task { await open() }
    }
    
    /// A screen in its own navigation, with a close button.
    private func closable(@ViewBuilder _ content: () -> some View) -> some View {
        ElementNavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onClose) {
                            CompoundIcon(\.close)
                        }
                        .accessibilityLabel(L10n.actionClose)
                    }
                }
        }
    }
    
    private func open() async {
        let repository = service.repository
        // The latest copy first; offline, the phone's copy is what there is.
        _ = try? await repository.sync(roomID: roomID)
        let file = try? await repository.file(roomID: roomID, path: path)
        if let route = ArtiseNoteDocument.route(roomID: roomID, path: path, kind: kind ?? file?.kind) {
            if case .note = route, file?.content == nil {
                stage = .unavailable
            } else {
                stage = .screen(route)
            }
            return
        }
        guard NoteDocumentKind.of(path) == .image else {
            stage = .folder
            return
        }
        if let url = try? await repository.attachment(roomID: roomID, path: path) {
            previewURL = url
            stage = .quickLook
        } else {
            stage = .unavailable
        }
    }
}

/// The PDF viewer on its own, with a close button, for when there's no notes screen to push it from.
struct NotePDFSheet: View {
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    let onClose: () -> Void
    
    var body: some View {
        ElementNavigationStack {
            NotePDFScreen(service: service, roomID: roomID, path: path)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onClose) {
                            CompoundIcon(\.close)
                        }
                        .accessibilityLabel(L10n.actionClose)
                    }
                }
        }
    }
}

/// A PDF from the notes, page by page, from the phone's copy (downloaded first when it isn't there yet), with a
/// search field that finds words as they're typed and turns to the page of each match. An Office file shows the
/// server's PDF of it the same way; "Open with" always hands over the file itself.
struct NotePDFScreen: View {
    enum Source {
        case file
        /// A Word, Excel or PowerPoint file, read through the server's conversion.
        case office
    }
    
    let service: ArtiseNotesService
    let roomID: String
    let path: String
    var source = Source.file
    
    @State private var document: PDFDocument?
    @State private var search: NotePDFSearchModel?
    @State private var failed = false
    /// An Office file the server has no PDF of: its icon and a hint to use "Open with". Not an error.
    @State private var noConversion = false
    /// The file itself, for "Open with".
    @State private var original: URL?
    @State private var isSearching = false
    @State private var query = ""
    
    var body: some View {
        VStack(spacing: 0) {
            if isSearching, let search {
                NoteSearchBar(query: $query, status: search.status, onNext: { search.next() }, onPrevious: { search.previous() }) {
                    isSearching = false
                    query = ""
                }
                if let snippet = search.snippet {
                    // A match the viewer can't mark on the page: its words, under the field.
                    Text(snippet)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(.compound.bgSubtleSecondary)
                }
            }
            if let document {
                NotePDFView(document: document,
                            highlights: search?.selections ?? [],
                            current: search?.currentSelection,
                            page: search?.currentPage)
            } else if noConversion {
                NoteOfficeHint(kind: NoteDocumentKind.of(path))
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
            if let original {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: original) {
                        CompoundIcon(\.shareIos)
                    }
                    .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_open_with"))
                }
            }
            if document != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { isSearching.toggle() } label: {
                        CompoundIcon(\.search)
                    }
                    .accessibilityLabel(ArtiseNotesL10n.text("a11y_notes_find"))
                }
            }
        }
        .onChange(of: query) { _, query in
            search?.search(query)
        }
        .task { await load() }
    }
    
    private func load() async {
        let repository = service.repository
        let pdfURL: URL?
        switch source {
        case .file:
            pdfURL = try? await repository.attachment(roomID: roomID, path: path)
            original = pdfURL
        case .office:
            do {
                pdfURL = try await repository.officePDF(roomID: roomID, path: path)
            } catch NotesError.network {
                pdfURL = nil
            } catch {
                // Not converted (it failed, or an older server): the hint, and "Open with" for the file.
                noConversion = true
                pdfURL = nil
            }
            original = try? await repository.attachment(roomID: roomID, path: path)
        }
        guard let pdfURL, let loaded = PDFDocument(url: pdfURL) else {
            failed = !noConversion
            return
        }
        document = loaded
        let roomID = roomID
        let path = path
        search = NotePDFSearchModel(document: loaded) { try await repository.documentText(roomID: roomID, path: path) }
    }
}

/// Finding words in a PDF: on PDFKit's text layer when the document has one, highlighting every match on its page;
/// otherwise with the server's text (`GET /text`), turning to the match's page and showing its words, so a scanned
/// or odd PDF behaves the same as in the Android app. A file the server can't give text for says so.
@Observable
final class NotePDFSearchModel {
    enum Source: Equatable {
        case pdfKit
        case serverText
    }
    
    let document: PDFDocument
    let source: Source
    private let textProvider: () async throws -> NotesDocumentText
    
    private(set) var status = NoteSearchStatus.idle
    /// PDFKit's matches, every one highlighted.
    private(set) var selections: [PDFSelection] = []
    /// The server text's matches.
    private(set) var matches: [DocumentMatch] = []
    private(set) var cursor = SearchCursor(count: 0)
    private var serverText: NotesDocumentText?
    private var serverUnavailable = false
    private var running: Task<Void, Never>?
    
    init(document: PDFDocument, textProvider: @escaping () async throws -> NotesDocumentText) {
        self.document = document
        self.textProvider = textProvider
        source = Self.hasTextLayer(document) ? .pdfKit : .serverText
    }
    
    /// Whether PDFKit can read any words in the document.
    static func hasTextLayer(_ document: PDFDocument) -> Bool {
        !(document.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var currentSelection: PDFSelection? {
        guard source == .pdfKit, let index = cursor.index, selections.indices.contains(index) else { return nil }
        return selections[index]
    }
    
    /// The page (from 1) of the current match, for a document searched with the server's text.
    var currentPage: Int? {
        guard source == .serverText, let index = cursor.index, matches.indices.contains(index) else { return nil }
        return matches[index].page
    }
    
    /// The current match's words, when they can't be marked on the page.
    var snippet: String? {
        guard source == .serverText, let index = cursor.index, matches.indices.contains(index),
              let page = serverText?.pages.first(where: { $0.number == matches[index].page }) else { return nil }
        return DocumentSearch.snippet(around: matches[index].range, in: page.text)
    }
    
    /// Finds `query` as it's typed. A search that's still running when the next letter comes is dropped.
    func search(_ query: String) {
        running?.cancel()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            selections = []
            matches = []
            cursor = SearchCursor(count: 0)
            status = serverUnavailable ? .unavailable : .idle
            return
        }
        running = Task { await find(needle) }
    }
    
    /// Waits for a search started by `search` to finish, for tests.
    func waitForSearch() async {
        await running?.value
    }
    
    private func find(_ needle: String) async {
        switch source {
        case .pdfKit:
            // The same matching as everywhere else (case and accents don't matter), on each page's text layer, turned
            // into PDFKit selections so they're marked on the page.
            var found: [PDFSelection] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let text = page.string ?? ""
                for range in DocumentSearch.ranges(of: needle, in: text) {
                    if let selection = page.selection(for: NSRange(location: range.lowerBound, length: range.count)) {
                        found.append(selection)
                    }
                }
            }
            guard !Task.isCancelled else { return }
            for selection in found {
                selection.color = NoteFindHighlight.match
            }
            selections = found
            matches = []
            cursor = SearchCursor(count: found.count)
            markCurrent()
        case .serverText:
            if serverText == nil, !serverUnavailable {
                do {
                    serverText = try await textProvider()
                } catch {
                    // Too big, a kind with no text, or no connection: the field says search isn't available.
                    serverUnavailable = true
                }
            }
            guard !Task.isCancelled else { return }
            guard let serverText else {
                status = .unavailable
                return
            }
            let found = DocumentSearch.matches(for: needle, in: serverText.pages)
            matches = found
            selections = []
            cursor = SearchCursor(count: found.count)
        }
        updateStatus()
    }
    
    func next() {
        cursor.next()
        markCurrent()
        updateStatus()
    }
    
    func previous() {
        cursor.previous()
        markCurrent()
        updateStatus()
    }
    
    /// The current match stands out from the others.
    private func markCurrent() {
        for (index, selection) in selections.enumerated() {
            selection.color = index == cursor.index ? NoteFindHighlight.current : NoteFindHighlight.match
        }
    }
    
    private func updateStatus() {
        if let position = cursor.position {
            status = .found(position: position, total: cursor.count)
        } else {
            status = serverUnavailable ? .unavailable : .none
        }
    }
}

/// PDFKit's view: pages one under the other, fitted to the width. Matches are marked on their pages, and the view
/// turns to the current one (or to the page a server-text match is on).
struct NotePDFView: UIViewRepresentable {
    let document: PDFDocument
    var highlights: [PDFSelection] = []
    var current: PDFSelection?
    var page: Int?
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .compound.bgCanvasDefault
        view.document = document
        return view
    }
    
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
        view.highlightedSelections = highlights.isEmpty ? nil : highlights
        if let current, current !== context.coordinator.lastCurrent {
            view.go(to: current)
        }
        context.coordinator.lastCurrent = current
        if let page, page != context.coordinator.lastPage, let pdfPage = document.page(at: page - 1) {
            view.go(to: pdfPage)
        }
        context.coordinator.lastPage = page
    }
    
    final class Coordinator {
        var lastCurrent: PDFSelection?
        var lastPage: Int?
    }
}
