//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Compound
import SwiftUI

/// Where a notes screen leads. Each screen pushes the next with `navigationDestination(item:)`.
enum NotesRoute: Hashable {
    case chat(roomID: String, name: String)
    case folder(roomID: String, path: String)
    case note(roomID: String, path: String)
    /// A note just created: it opens in the editor.
    case newNote(roomID: String, path: String)
    /// "Choose a version" for the chat's changes that need a choice.
    case choices(roomID: String)
    /// The chat's photos and files.
    case media(roomID: String)
    /// A PDF, page by page.
    case pdf(roomID: String, path: String)
    /// A CSV's text.
    case table(roomID: String, path: String)
    /// A Word, Excel or PowerPoint file, as the server's PDF of it.
    case office(roomID: String, path: String)
    /// A chart, as the server draws it.
    case chart(roomID: String, path: String)
    /// A dashboard: its text and charts as one page the server draws.
    case dashboard(roomID: String, path: String)
    /// A dashboard just created: it opens with the editor on its layout.
    case newDashboard(roomID: String, path: String)
    /// The chat's notes as a map.
    case map(roomID: String)
    /// Every change to the chat's notes.
    case changes(roomID: String)
    case search(roomID: String)
    /// A note's saved versions, and one of them read-only.
    case noteHistory(roomID: String, path: String)
    case noteVersion(roomID: String, path: String, commit: String, at: String)
}

/// The notes screens, presented over the app: the chats with notes, or one chat's notes.
struct NotesRootView: View {
    let service: ArtiseNotesService
    let roomID: String?
    let onClose: () -> Void
    
    @State private var showsPrivacyNotice = false
    
    var body: some View {
        ElementNavigationStack {
            start
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onClose) {
                            CompoundIcon(\.close)
                        }
                        .accessibilityLabel(L10n.actionClose)
                    }
                }
        }
        .task { await showPrivacyNoticeOnce() }
        .alert(ArtiseNotesL10n.privacyTitle, isPresented: $showsPrivacyNotice) {
            Button(ArtiseNotesL10n.privacyOK) {
                Task { try? await service.repository.markPrivacyNoticeSeen() }
            }
        } message: {
            Text(ArtiseNotesL10n.privacyBody)
        }
    }
    
    @ViewBuilder
    private var start: some View {
        if let roomID {
            NotesFolderScreen(service: service, roomID: roomID, folder: "", title: nil)
        } else {
            NotesChatsScreen(service: service)
        }
    }
    
    /// "Ari can read notes": shown once per account, the first time notes open.
    private func showPrivacyNoticeOnce() async {
        let hasSeen = await (try? service.repository.hasSeenPrivacyNotice()) ?? false
        showsPrivacyNotice = !hasSeen
    }
}

/// The screen a route leads to.
struct NotesDestination: View {
    let service: ArtiseNotesService
    let route: NotesRoute
    
    var body: some View {
        switch route {
        case .chat(let roomID, let name):
            NotesFolderScreen(service: service, roomID: roomID, folder: "", title: name)
        case .folder(let roomID, let path):
            NotesFolderScreen(service: service, roomID: roomID, folder: path, title: nil)
        case .note(let roomID, let path):
            NoteScreen(service: service, roomID: roomID, path: path)
        case .newNote(let roomID, let path):
            NoteScreen(service: service, roomID: roomID, path: path, startsEditing: true)
        case .choices(let roomID):
            NotesChoicesScreen(service: service, roomID: roomID)
        case .media(let roomID):
            NotesMediaScreen(service: service, roomID: roomID)
        case .pdf(let roomID, let path):
            NotePDFScreen(service: service, roomID: roomID, path: path)
        case .table(let roomID, let path):
            NoteTableScreen(service: service, roomID: roomID, path: path)
        case .office(let roomID, let path):
            NotePDFScreen(service: service, roomID: roomID, path: path, source: .office)
        case .chart(let roomID, let path):
            NoteChartScreen(service: service, roomID: roomID, path: path)
        case .dashboard(let roomID, let path):
            NoteDashboardScreen(service: service, roomID: roomID, path: path)
        case .newDashboard(let roomID, let path):
            NoteDashboardScreen(service: service, roomID: roomID, path: path, startsEditing: true)
        case .map(let roomID):
            NotesMapScreen(service: service, roomID: roomID)
        case .changes(let roomID):
            NotesChangesScreen(service: service, roomID: roomID)
        case .search(let roomID):
            NotesSearchScreen(service: service, roomID: roomID)
        case .noteHistory(let roomID, let path):
            NoteHistoryScreen(service: service, roomID: roomID, path: path)
        case .noteVersion(let roomID, let path, let commit, let at):
            NoteVersionScreen(service: service, roomID: roomID, path: path, commit: commit, at: at)
        }
    }
}

/// How the last update of the notes went, shown above the list.
enum NotesSyncStatus: Equatable {
    case upToDate
    case offline
    case failed
    /// Some changes couldn't be sent yet; they go with the next update.
    case partial
    
    init(report: SyncReport) {
        self = report.failed > 0 ? .partial : .upToDate
    }
    
    init(error: Error) {
        if case NotesError.network = error {
            self = .offline
        } else {
            self = .failed
        }
    }
}

/// One line that says when the notes shown aren't the latest, and why.
struct NotesStatusLine: View {
    let status: NotesSyncStatus
    
    var body: some View {
        if let text {
            Label {
                Text(text)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            } icon: {
                CompoundIcon(icon, size: .small, relativeTo: .compound.bodySM)
                    .foregroundStyle(.compound.iconSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var icon: KeyPath<CompoundIcons, Image> {
        status == .offline ? \.offline : \.error
    }
    
    private var text: String? {
        switch status {
        case .upToDate: nil
        case .offline: ArtiseNotesL10n.offline
        case .failed: ArtiseNotesL10n.syncFailed
        case .partial: ArtiseNotesL10n.syncPartial
        }
    }
}
