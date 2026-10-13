//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseNotes
import Foundation
import MatrixRustSDK

/// One account's notes: the sync engine over its encrypted store, and live updates from the chats' room state.
@MainActor
final class ArtiseNotesService {
    /// The room state event the Ari bot sets whenever a chat's notes change: `{"tree": "9f1c…"}`.
    static let stateEventType = "co.artise.notes"
    
    let repository: NotesRepository
    private let clientProxy: ClientProxyProtocol
    private var followed: [String: TaskHandle] = [:]
    
    /// `nil` when the account's notes can't be opened on this phone (no key in the Keychain).
    init?(clientProxy: ClientProxyProtocol) {
        guard let sdkClient = (clientProxy as? ClientProxy)?.client else {
            MXLog.error("Artise notes need the SDK client")
            return nil
        }
        let userID = clientProxy.userID
        let keyData: Data
        do {
            keyData = try KeychainNotesKeyStore().key(account: userID)
        } catch {
            MXLog.error("Artise notes have no key: \(error)")
            return nil
        }
        let tokenSource = OpenIDNotesTokenSource {
            let token = try await sdkClient.requestOpenidToken()
            return NotesOpenIDToken(accessToken: token.accessToken, expiresIn: TimeInterval(token.expiresInSeconds))
        }
        let files = NotesFileOptions(cacheDirectory: Self.cacheDirectory(for: userID),
                                     pendingDirectory: Self.directory(for: userID).appending(path: "pending"),
                                     convertPhoto: { NotesPhotoConverter.toJPEG($0, contentType: $1) },
                                     canPrefetch: { NotesPrefetchPolicy.shared.canPrefetch })
        repository = NotesSyncEngine(api: NotesAPIClient(tokenSource: tokenSource),
                                     directory: Self.directory(for: userID),
                                     cipher: AESGCMNotesCipher(keyData: keyData),
                                     files: files)
        self.clientProxy = clientProxy
    }
    
    /// Where an account's notes live on the phone.
    nonisolated static func directory(for userID: String) -> URL {
        let folder = Data(userID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return URL.applicationSupportDirectory.appending(path: "ArtiseNotes").appending(path: folder)
    }
    
    /// Where an account's downloaded photos and files are kept; iOS may clear it when space runs low.
    nonisolated static func cacheDirectory(for userID: String) -> URL {
        URL.cachesDirectory.appending(path: "ArtiseNotes").appending(path: directory(for: userID).lastPathComponent)
    }
    
    /// Forgets an account's notes on this phone: the files, the downloads, then the key that could read them.
    nonisolated static func removeData(forUserID userID: String) {
        try? FileManager.default.removeItem(at: directory(for: userID))
        try? FileManager.default.removeItem(at: cacheDirectory(for: userID))
        KeychainNotesKeyStore().deleteKey(account: userID)
    }
    
    // MARK: - Live updates
    
    /// Keeps these chats' notes current while a notes screen shows them, as the Notes API contract asks:
    /// when a chat's `co.artise.notes` tree differs from ours, it syncs; a chat without that state gets one
    /// ETag check instead, which costs a `304` when nothing changed.
    func follow(roomID: String) async {
        guard followed[roomID] == nil else { return }
        guard case let .joined(roomProxy) = await clientProxy.roomForIdentifier(roomID),
              let room = (roomProxy as? JoinedRoomProxy)?.room else {
            // Not a room this phone knows: the ETag check is all there is.
            repository.syncInBackground(roomID: roomID)
            return
        }
        let repository = repository
        let listener = NotesTreeListener { tree in
            Task {
                if let tree {
                    _ = try? await repository.onTreeChanged(roomID: roomID, tree: tree)
                } else {
                    _ = try? await repository.sync(roomID: roomID)
                }
            }
        }
        followed[roomID] = room.subscribeToStateEvents(eventType: stateEventTypeFromString(s: Self.stateEventType), listener: listener)
    }
    
    func unfollowAll() {
        followed.values.forEach { $0.cancel() }
        followed = [:]
    }
}

/// Hears a chat's `co.artise.notes` state: the tree hash, or `nil` when the chat has none yet.
final nonisolated class NotesTreeListener: RoomStateEventsListener {
    private let onTree: @Sendable (String?) -> Void
    
    init(onTree: @escaping @Sendable (String?) -> Void) {
        self.onTree = onTree
    }
    
    func onUpdate(events: [RoomStateEvent]) {
        let content = events.first { $0.stateKey.isEmpty }?.contentJson
        onTree(content.flatMap(Self.tree))
    }
    
    /// The tree hash from `{"tree": "9f1c…"}`, or `nil` if it's missing or unreadable.
    static func tree(from content: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any],
              let tree = object["tree"] as? String, !tree.isEmpty else { return nil }
        return tree
    }
}
