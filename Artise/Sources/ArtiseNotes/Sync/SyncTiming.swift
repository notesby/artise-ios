//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

/// How long each step of one sync took and how much it moved, for the app's logs: it shows whether downloading
/// notes one request at a time is what makes syncs slow. Counts and times only, never names or text.
struct SyncTiming {
    var editsMillis = 0
    var treeMillis = 0
    /// False for a `304`: nothing changed.
    var treeChanged = false
    var treeFiles = 0
    var notes = 0
    var noteBytes: Int64 = 0
    var batches = 0
    var downloadMillis = 0
    var saveMillis = 0
    var uploadsMillis = 0
    var sent = 0
    
    private let started = ContinuousClock.now
    
    /// Runs `body` and adds its time to `key`.
    mutating func measure<T>(_ key: WritableKeyPath<SyncTiming, Int>, _ body: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        defer { self[keyPath: key] += Self.millis(since: start) }
        return try await body()
    }
    
    /// "Notes sync timing: total 2710 ms, edits 0 ms, tree 180 ms (changed, 40 files), notes 12 (34 KB) in 3 batches
    /// 2400 ms (800 ms per batch), saving 90 ms, uploads 0 ms, sent 0".
    func line(failed: Bool) -> String {
        let tree = treeChanged ? "changed, \(treeFiles) files" : "unchanged"
        let perBatch = batches > 0 ? ", \(downloadMillis / batches) ms per batch" : ""
        return "Notes sync timing: \(failed ? "failed after" : "total") \(Self.millis(since: started)) ms, "
            + "edits \(editsMillis) ms, tree \(treeMillis) ms (\(tree)), "
            + "notes \(notes) (\(max(noteBytes, 0) / 1024) KB) in \(batches) batches \(downloadMillis) ms\(perBatch), "
            + "saving \(saveMillis) ms, uploads \(uploadsMillis) ms, sent \(sent)"
    }
    
    private static func millis(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
