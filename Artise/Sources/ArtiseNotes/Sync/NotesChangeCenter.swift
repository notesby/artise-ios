//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Tells open screens when the phone's copy of a chat's notes changed: a local edit, a choice, or a sync.
actor NotesChangeCenter {
    private var subscribers: [UUID: (roomID: String, continuation: AsyncStream<Void>.Continuation)] = [:]
    
    func changes(of roomID: String) -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = (roomID, continuation)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        return stream
    }
    
    func notify(_ roomID: String) {
        for subscriber in subscribers.values where subscriber.roomID == roomID {
            subscriber.continuation.yield()
        }
    }
    
    private func remove(_ id: UUID) {
        subscribers[id] = nil
    }
}
