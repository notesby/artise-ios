//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// Searches the chat's notes on the phone (works offline), as on Android: names first, with the matching lines.
struct NotesSearchScreen: View {
    let service: ArtiseNotesService
    let roomID: String
    
    @State private var query = ""
    @State private var results: [NotesSearchResult] = []
    @State private var route: NotesRoute?
    @State private var hasSearched = false
    
    var body: some View {
        Form {
            if hasSearched, results.isEmpty, !trimmedQuery.isEmpty {
                Section {
                    Text(String(format: ArtiseNotesL10n.text("screen_notes_search_empty"), trimmedQuery))
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                }
            }
            if !results.isEmpty {
                Section {
                    ForEach(results, id: \.path) { result in
                        ListRow(label: .default(title: NotesFolderEntries.noteName(result.path),
                                                description: result.lines.isEmpty ? nil : result.lines.joined(separator: "\n"),
                                                icon: \.document),
                                kind: .navigationLink { route = .note(roomID: roomID, path: result.path) })
                    }
                }
            }
        }
        .compoundList()
        .navigationTitle(ArtiseNotesL10n.text("a11y_notes_search"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: ArtiseNotesL10n.text("screen_notes_search_placeholder"))
        .navigationDestination(item: $route) { route in
            NotesDestination(service: service, route: route)
        }
        .task(id: query) {
            // A short pause, so each letter typed doesn't search again.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let files = await (try? service.repository.files(roomID: roomID)) ?? []
            results = LocalNotesSearch.search(files, query: query)
            hasSearched = true
        }
        .onAppear { ArtiseAnalyticsClient.shared.screen(.notesSearch) }
    }
    
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }
}
