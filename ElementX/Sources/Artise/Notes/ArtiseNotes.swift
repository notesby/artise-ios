//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Network
import SwiftUI

/// Notes for the signed-in account, and the one place the app opens them from.
///
/// Upstream screens open notes with a single call (`ArtiseNotes.shared.open(roomID:)`), so the upstream
/// changes for the entry points stay one line each.
@MainActor
final class ArtiseNotes {
    static let shared = ArtiseNotes()
    
    private(set) var service: ArtiseNotesService?
    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var pathMonitor: NWPathMonitor?
    private var wasOffline = false
    private var checks: Task<Void, Never>?
    
    /// While the app is open, notes nobody is looking at are checked this often (an unchanged chat costs a `304`).
    static let checkInterval = Duration.seconds(5 * 60)
    
    var isAvailable: Bool {
        service != nil
    }
    
    /// Called when an account's session is ready, with `nil` when it's gone, and again when its workspace's notes
    /// API changes. A workspace without one has no notes.
    func configure(with userSession: UserSessionProtocol?) {
        service?.unfollowAll()
        service?.stopWatching()
        guard let userSession, let notesAPIURL = ArtiseWorkspaces.shared.notesAPIURL else {
            service = nil
            stopChecking()
            return
        }
        service = ArtiseNotesService(clientProxy: userSession.clientProxy, notesAPIURL: notesAPIURL)
        // Notas is already current when opened: the chats on this phone sync now and each time the app comes back.
        foregroundObserver = foregroundObserver ?? NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                                                          object: nil, queue: .main) { _ in
            Task { @MainActor in
                ArtiseNotes.shared.startChecking()
                await ArtiseNotes.shared.syncKnownChats()
            }
        }
        // Leaving the app gives a sync in progress (a photo going up) up to iOS's background time to finish.
        backgroundObserver = backgroundObserver ?? NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                                                          object: nil, queue: .main) { _ in
            Task { @MainActor in
                ArtiseNotes.shared.stopChecking()
                await ArtiseNotes.shared.finishInBackground()
            }
        }
        startWatchingTheConnection()
        startChecking()
        Task { await syncKnownChats() }
    }
    
    /// Every few minutes while the app is open: syncs the chats on this phone and follows any new ones live, when the
    /// background setting allows the connection.
    private func startChecking() {
        checks?.cancel()
        checks = Task { [weak self] in
            await self?.service?.watchKnownChats()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.checkInterval)
                guard !Task.isCancelled else { return }
                await self?.syncInBackground()
            }
        }
    }
    
    private func stopChecking() {
        checks?.cancel()
        checks = nil
    }
    
    /// A sync nobody asked for (while the app is open on another screen, or when iOS wakes it): only on the connections
    /// the person chose, and never in Low Data Mode.
    func syncInBackground() async {
        guard let service else { return }
        guard NotesPrefetchPolicy.shared.canSyncInBackground else {
            MXLog.info("Notes: background update skipped on this connection")
            return
        }
        await syncKnownChats()
        await service.watchKnownChats()
    }
    
    /// Edits and photos waiting offline go out as soon as the connection is back.
    private func startWatchingTheConnection() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in ArtiseNotes.shared.connectionChanged(isOnline: isOnline) }
        }
        monitor.start(queue: DispatchQueue(label: "co.artise.notes.connection"))
        pathMonitor = monitor
    }
    
    private func connectionChanged(isOnline: Bool) {
        defer { wasOffline = !isOnline }
        guard isOnline, wasOffline else { return }
        MXLog.info("Notes: back online, sending what waited")
        Task { await syncKnownChats() }
    }
    
    private func finishInBackground() async {
        guard service != nil else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "Artise notes") { }
        await syncKnownChats()
        UIApplication.shared.endBackgroundTask(task)
    }
    
    /// The server's silent push for a chat whose notes changed: updates that chat if its notes are on this phone,
    /// on the connections the person chose. After a launch in the background, waits a little for the account.
    func handlePush(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let roomID = NotesPush.roomID(from: userInfo) else { return .noData }
        for _ in 0..<20 where service == nil {
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard let service else { return .noData }
        guard NotesPrefetchPolicy.shared.canSyncInBackground else {
            MXLog.info("Notes: push skipped on this connection")
            return .noData
        }
        guard await service.repository.knownRoomIDs().contains(roomID) else { return .noData }
        do {
            let report = try await service.repository.sync(roomID: roomID)
            MXLog.info("Notes: push synced \(roomID)")
            return report.changedAnything ? .newData : .noData
        } catch {
            MXLog.error("Notes: push sync failed: \(error)")
            return .failed
        }
    }
    
    /// Syncs the chats this phone holds notes for (an unchanged one costs a `304`); also run by background refresh.
    func syncKnownChats() async {
        guard let service else { return }
        let started = Date.now
        let synced = await service.repository.syncKnownChats(concurrency: 3)
        MXLog.info("Notes: synced \(synced) chats in \(Int(Date.now.timeIntervalSince(started) * 1000)) ms")
    }
    
    /// The account signed out: stops its notes and forgets them on this phone (files and key).
    func signOut(userID: String) {
        stopChecking()
        service?.stopWatching()
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
    
    /// Opens a file Ari posted from the notes at its path there: a note in the editor, a PDF in the viewer, a photo as
    /// itself, after updating the chat's notes so it's the current copy. `false` when notes aren't available here,
    /// so the attachment opens as it always did.
    @discardableResult
    func openDocument(roomID: String, path: String, kind: NoteDocumentKind? = nil) -> Bool {
        guard let service, let presenter = UIViewController.artiseTopViewController() else { return false }
        weak var host: UIViewController?
        let root = ArtiseNoteDocumentView(service: service, roomID: roomID, path: path, kind: kind) {
            host?.dismiss(animated: true)
        }
        let controller = UIHostingController(rootView: root.artiseWorkspaceAccent())
        controller.modalPresentationStyle = .fullScreen
        host = controller
        presenter.present(controller, animated: true)
        return true
    }
}

/// Starts and stops the workspace, notes, stickers and link previews with the account's session.
nonisolated struct ArtiseUserSessionHook: UserSessionHookProtocol {
    func configure(with userSession: UserSessionProtocol?) async {
        await ArtiseWorkspaces.shared.configure(with: userSession)
        await ArtiseRecoveryKeys.shared.configure(with: userSession)
        await ArtiseNotes.shared.configure(with: userSession)
        await ArtiseStickers.shared.configure(with: userSession)
        await ArtiseLinkPreviews.shared.configure(with: userSession)
    }
}
