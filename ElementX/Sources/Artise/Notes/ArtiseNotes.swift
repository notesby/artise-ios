//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI

/// Notes for the signed-in account, and the one place the app opens them from.
///
/// Upstream screens open notes with a single call (`ArtiseNotes.shared.open(roomID:)`), so the upstream
/// changes for the entry points stay one line each.
@MainActor
final class ArtiseNotes {
    static let shared = ArtiseNotes()
    
    private(set) var service: ArtiseNotesService?
    
    var isAvailable: Bool {
        service != nil
    }
    
    /// Called when an account's session is ready, and with `nil` when it's gone.
    func configure(with userSession: UserSessionProtocol?) {
        service?.unfollowAll()
        service = userSession.flatMap { ArtiseNotesService(clientProxy: $0.clientProxy) }
    }
    
    /// The account signed out: stops its notes and forgets them on this phone (files and key).
    func signOut(userID: String) {
        service?.unfollowAll()
        service = nil
        ArtiseNotesService.removeData(forUserID: userID)
    }
    
    /// Opens the notes: a chat's notes with `roomID`, otherwise the list of chats with notes.
    func open(roomID: String?) {
        guard let service, let presenter = UIViewController.artiseTopViewController() else {
            MXLog.error("Artise notes can't open right now")
            return
        }
        weak var host: UIViewController?
        let root = NotesRootView(service: service, roomID: roomID) { [weak service] in
            service?.unfollowAll()
            host?.dismiss(animated: true)
        }
        let controller = UIHostingController(rootView: root.artiseWorkspaceAccent())
        controller.modalPresentationStyle = .fullScreen
        host = controller
        presenter.present(controller, animated: true)
    }
}

/// Starts and stops the workspace, notes, stickers and link previews with the account's session.
nonisolated struct ArtiseUserSessionHook: UserSessionHookProtocol {
    func configure(with userSession: UserSessionProtocol?) async {
        await ArtiseWorkspaces.shared.configure(with: userSession)
        await ArtiseNotes.shared.configure(with: userSession)
        await ArtiseStickers.shared.configure(with: userSession)
        await ArtiseLinkPreviews.shared.configure(with: userSession)
    }
}
