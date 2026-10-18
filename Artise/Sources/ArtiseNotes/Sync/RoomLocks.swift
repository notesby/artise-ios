//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore

/// One lock per chat, so a chat's queue is never sent twice at once, while different chats don't wait for each other.
actor RoomLocks {
    private var locks: [String: AsyncLock] = [:]
    
    func lock(for roomID: String) -> AsyncLock {
        if let lock = locks[roomID] {
            return lock
        }
        let lock = AsyncLock()
        locks[roomID] = lock
        return lock
    }
}

extension RoomLocks {
    func withLock<T: Sendable, E: Error>(_ roomID: String, _ body: () async throws(E) -> T) async throws(E) -> T {
        let lock = lock(for: roomID)
        await lock.lock()
        do {
            let result = try await body()
            await lock.unlock()
            return result
        } catch {
            await lock.unlock()
            throw error
        }
    }
}
