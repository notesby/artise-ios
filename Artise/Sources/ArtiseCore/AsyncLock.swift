//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A lock that waits without blocking a thread, held across `await`s. Waiters go in order.
public actor AsyncLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    public init() { }
    
    public func lock() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
    
    public func unlock() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            // The lock passes straight to the next waiter, so it stays locked.
            waiters.removeFirst().resume()
        }
    }
}

public extension AsyncLock {
    /// Runs `body` holding the lock, and lets go whether it finishes or throws.
    nonisolated(nonsending) func withLock<T: Sendable, E: Error>(_ body: () async throws(E) -> T) async throws(E) -> T {
        await lock()
        do {
            let result = try await body()
            await unlock()
            return result
        } catch {
            await unlock()
            throw error
        }
    }
}
