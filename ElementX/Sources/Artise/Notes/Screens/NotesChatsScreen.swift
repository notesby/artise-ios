//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// The chats that have notes, opened from the chats list's top bar.
struct NotesChatsScreen: View {
    let service: ArtiseNotesService
    
    @State private var chats: [NotesChat] = []
    @State private var hasLoaded = false
    @State private var status = NotesSyncStatus.upToDate
    @State private var route: NotesRoute?
    
    var body: some View {
        Form {
            if status != .upToDate {
                Section {
                    NotesStatusLine(status: status)
                }
            }
            
            if hasLoaded, chats.isEmpty {
                Section {
                    Text(ArtiseNotesL10n.chatsEmpty)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                }
            } else {
                Section {
                    ForEach(chats, id: \.roomID) { chat in
                        ListRow(label: .default(title: chat.name, icon: \.document),
                                kind: .navigationLink { route = .chat(roomID: chat.roomID, name: chat.name) })
                    }
                }
            }
        }
        .compoundList()
        .navigationTitle(ArtiseNotesL10n.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .navigationDestination(item: $route) { route in
            NotesDestination(service: service, route: route)
        }
        .task {
            chats = await (try? service.repository.cachedChats()) ?? []
            hasLoaded = !chats.isEmpty
            await refresh()
        }
    }
    
    private func refresh() async {
        do {
            chats = try await service.repository.refreshChats()
            status = .upToDate
        } catch {
            status = NotesSyncStatus(error: error)
        }
        hasLoaded = true
    }
}
