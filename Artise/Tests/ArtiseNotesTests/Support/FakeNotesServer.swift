//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import ArtiseNotes
import Foundation
import Synchronization
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An in-memory Notes API that follows the contract closely enough to test syncing against it.
final class FakeNotesServer: NotesHTTPTransport {
    struct Recorded: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data?
        
        var path: String {
            url.path
        }
        
        var query: [String: String] {
            Dictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
                       uniquingKeysWith: { $1 })
        }
        
        var json: [String: Any]? {
            body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }
    
    struct StoredFile {
        var version: String
        var content: String
        var isNote: Bool
    }
    
    struct State {
        var files: [String: StoredFile] = [:]
        var folders: [String] = []
        /// What `GET /pages` answers.
        var pages: [NotesPage] = []
        /// What `GET /preview` answers for a path, with its ETag; a PDF or photo without one is "unreadable".
        var previews: [String: (png: Data, etag: String)] = [:]
        /// What `GET /text` answers for a PDF, page by page; one without an entry is "too big".
        var texts: [String: [String]] = [:]
        /// What `GET /pdf` answers for an Office file; one without an entry couldn't be converted.
        var pdfs: [String: Data] = [:]
        var versionCounter = 0
        var treeCounter = 0
        var requests: [Recorded] = []
        /// Tokens the server accepts; any other gets a `401`.
        var validTokens: Set = ["token-1"]
        /// Answers the next requests to these endpoints (`note`, `tree`…) with a status and a JSON error, once each.
        var failNext: [String: [(status: Int, body: String)]] = [:]
        /// When set, every request fails as if offline.
        var isOffline = false
        /// Merges a save whose base is outdated when it returns text; otherwise the save answers `409 conflict`.
        var merge: (@Sendable (_ server: String, _ mine: String) -> String?)?
    }
    
    static let roomID = "!abc:artise.co"
    static let encodedRoom = "%21abc%3Aartise.co"
    
    let state = Mutex(State())
    
    // MARK: - Setting up and checking
    
    var tree: String {
        state.withLock { "tree-\($0.treeCounter)" }
    }
    
    var requests: [Recorded] {
        state.withLock { $0.requests }
    }
    
    func requests(to endpoint: String, method: String? = nil) -> [Recorded] {
        requests.filter { $0.path.hasSuffix("/" + endpoint) && (method == nil || $0.method == method) }
    }
    
    func setOffline(_ isOffline: Bool) {
        state.withLock { $0.isOffline = isOffline }
    }
    
    func setValidTokens(_ tokens: Set<String>) {
        state.withLock { $0.validTokens = tokens }
    }
    
    func setMerge(_ merge: (@Sendable (_ server: String, _ mine: String) -> String?)?) {
        state.withLock { $0.merge = merge }
    }
    
    /// The next request to `endpoint` fails with `status` and this error code; the one after works again.
    func failNext(_ endpoint: String, status: Int, error: String) {
        let body = #"{"error": "\#(error)", "message": "Failed on purpose"}"#
        state.withLock { $0.failNext[endpoint, default: []].append((status, body)) }
    }
    
    @discardableResult
    func put(_ path: String, _ content: String, isNote: Bool = true) -> String {
        state.withLock { Self.store(&$0, path, content, isNote: isNote) }
    }
    
    func remove(_ path: String) {
        state.withLock {
            $0.files[path] = nil
            $0.treeCounter += 1
        }
    }
    
    func setFolders(_ folders: [String]) {
        state.withLock {
            $0.folders = folders
            $0.treeCounter += 1
        }
    }
    
    func setPages(_ pages: [NotesPage]) {
        state.withLock { $0.pages = pages }
    }
    
    func setPreview(_ path: String, png: Data, etag: String) {
        state.withLock { $0.previews[path] = (png, etag) }
    }
    
    func setPDF(_ path: String, pdf: Data) {
        state.withLock { $0.pdfs[path] = pdf }
    }
    
    func setText(_ path: String, pages: [String]) {
        state.withLock { $0.texts[path] = pages }
    }
    
    func content(_ path: String) -> String? {
        state.withLock { $0.files[path]?.content }
    }
    
    func version(_ path: String) -> String? {
        state.withLock { $0.files[path]?.version }
    }
    
    // MARK: - Transport
    
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(fileURLWithPath: "/")
        let recorded = Recorded(method: request.httpMethod ?? "GET", url: url, headers: request.allHTTPHeaderFields ?? [:], body: request.httpBody)
        let answer = state.withLock { state -> (Int, Data, [String: String])? in
            state.requests.append(recorded)
            if state.isOffline {
                return nil
            }
            return Self.answer(recorded, &state)
        }
        guard let (status, data, headers) = answer else {
            throw URLError(.notConnectedToInternet)
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
    
    private static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
    
    private static func answer(_ request: Recorded, _ state: inout State) -> (Int, Data, [String: String]) {
        let token = request.headers["Authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        guard state.validTokens.contains(token) else {
            return (401, json(["error": "unauthorized", "message": "Sign in again"]), [:])
        }
        let endpoint = request.path.split(separator: "/").last.map(String.init) ?? ""
        if var failures = state.failNext[endpoint], !failures.isEmpty {
            let failure = failures.removeFirst()
            state.failNext[endpoint] = failures
            return (failure.status, Data(failure.body.utf8), [:])
        }
        let (status, body, headers) = route(request, endpoint: endpoint, &state)
        return (status, (body as? Data) ?? json(body), headers)
    }
    
    private static func route(_ request: Recorded, endpoint: String, _ state: inout State) -> (Int, Any, [String: String]) {
        let path = request.query["path"] ?? ""
        switch (request.method, endpoint) {
        case ("GET", "chats"):
            return (200, ["user": "@ana:artise.co", "chats": [["id": roomID, "name": "Familia", "tree": "tree-\(state.treeCounter)"]]], [:])
        case ("GET", "tree"):
            let etag = "\"tree-\(state.treeCounter)\""
            if request.headers["If-None-Match"] == etag {
                return (304, Data(), ["ETag": etag])
            }
            let list = state.files.sorted { $0.key < $1.key }.map { path, file in
                ["path": path, "version": file.version, "size": file.content.utf8.count, "modified": 1_790_000_000, "note": file.isNote] as [String: Any]
            }
            return (200, ["tree": "tree-\(state.treeCounter)", "files": list, "folders": state.folders], ["ETag": etag])
        case ("GET", "note"):
            guard let file = state.files[path] else {
                return (404, ["error": "not_found", "message": "No such file"], [:])
            }
            return (200, ["path": path, "version": file.version, "content": file.content], [:])
        case ("PUT", "note"):
            return save(request.json ?? [:], &state)
        case ("GET", "raw"):
            guard let file = state.files[path] else {
                return (404, ["error": "not_found", "message": "No such file"], [:])
            }
            return (200, Data(file.content.utf8), ["ETag": file.version])
        case ("PUT", "raw"):
            if let existing = state.files[path], request.query["base"] == nil {
                return (409, ["error": "exists", "message": "Already there", "current": ["path": path, "version": existing.version]], [:])
            }
            let version = store(&state, path, String(decoding: request.body ?? Data(), as: UTF8.self), isNote: false)
            return (201, ["path": path, "version": version], [:])
        case ("POST", "move"):
            let body = request.json ?? [:]
            guard let from = body["from"] as? String, let to = body["to"] as? String else {
                return (400, ["error": "bad_path", "message": "Missing fields"], [:])
            }
            if body["folder"] as? Bool == true {
                var moved: [[String: Any]] = []
                for (file, stored) in state.files where file.hasPrefix(from + "/") {
                    let target = to + file.dropFirst(from.count)
                    state.files[file] = nil
                    state.files[target] = stored
                    moved.append(["from": file, "to": target, "version": stored.version])
                }
                state.folders = state.folders.map { $0 == from || $0.hasPrefix(from + "/") ? to + $0.dropFirst(from.count) : $0 }
                state.treeCounter += 1
                return (200, ["from": from, "to": to, "moved": moved, "links_updated": []], [:])
            }
            guard let stored = state.files[from] else {
                return (404, ["error": "not_found", "message": "No such file"], [:])
            }
            guard state.files[to] == nil else {
                return (409, ["error": "exists", "message": "Taken"], [:])
            }
            state.files[from] = nil
            state.files[to] = stored
            state.treeCounter += 1
            return (200, ["from": from, "to": to, "version": stored.version, "links_updated": []], [:])
        case ("POST", "folder"):
            let folder = request.json?["path"] as? String ?? ""
            state.folders.append(folder)
            state.treeCounter += 1
            return (201, ["path": folder], [:])
        case ("DELETE", "folder"):
            let inside = state.files.keys.filter { $0.hasPrefix(path + "/") }
            if !inside.isEmpty, request.query["recursive"] != "true" {
                return (409, ["error": "not_empty", "message": "Not empty", "files": inside.count, "folders": 0], [:])
            }
            inside.forEach { state.files[$0] = nil }
            state.folders.removeAll { $0 == path || $0.hasPrefix(path + "/") }
            state.treeCounter += 1
            return (200, ["path": path, "deleted": true, "notes": inside.count, "files": 0], [:])
        case ("GET", "pages"):
            let pages = state.pages.map { page in
                ["path": page.path, "title": page.title, "type": page.type, "folder": page.folder,
                 "aliases": page.aliases, "summary": page.summary, "note": page.isNote] as [String: Any]
            }
            return (200, ["pages": pages], [:])
        case ("GET", "preview"):
            guard let file = state.files[path] else {
                return (404, ["error": "not_found", "message": "No such file"], [:])
            }
            if let preview = state.previews[path] {
                if request.headers["If-None-Match"] == preview.etag {
                    return (304, Data(), ["ETag": preview.etag])
                }
                return (200, preview.png, ["Content-Type": "image/png", "ETag": preview.etag, "X-Width": "128", "X-Height": "96"])
            }
            if file.isNote {
                let lines = file.content.split(separator: "\n", omittingEmptySubsequences: false).prefix(40)
                return (200, Data(lines.joined(separator: "\n").utf8), ["Content-Type": "text/plain; charset=utf-8"])
            }
            if path.lowercased().hasSuffix(".pdf") || NotesFolderEntries.isImage(path) {
                return (422, ["error": "unreadable", "message": "Couldn't read it"], [:])
            }
            return (415, ["error": "no_preview", "message": "No preview for this kind"], [:])
        case ("GET", "text"):
            guard let file = state.files[path] else {
                return (404, ["error": "not_found", "message": "No such file"], [:])
            }
            if file.isNote {
                return (200, ["path": path, "version": file.version, "pages": [["n": 1, "text": file.content]]], [:])
            }
            if let pages = state.texts[path] {
                return (200, ["path": path, "version": file.version,
                              "pages": pages.enumerated().map { ["n": $0.offset + 1, "text": $0.element] as [String: Any] }], [:])
            }
            if path.lowercased().hasSuffix(".pdf") {
                return (413, ["error": "too_big", "message": "Too big"], [:])
            }
            return (415, ["error": "no_text", "message": "No text for this kind"], [:])
        case ("GET", "pdf"):
            guard state.files[path] != nil else {
                return (404, ["error": "not_found", "message": "No such file"], [:])
            }
            if let pdf = state.pdfs[path] {
                return (200, pdf, ["Content-Type": "application/pdf"])
            }
            if NoteDocumentKind.of(path) == .office {
                return (422, ["error": "unreadable", "message": "Couldn't convert it"], [:])
            }
            return (415, ["error": "no_pdf", "message": "Not an Office file"], [:])
        case ("GET", "links"):
            let name = path.split(separator: "/").last.map(String.init) ?? path
            let backlinks = state.files.filter { $0.value.isNote && $0.value.content.contains(name) }.keys.sorted()
                .map { ["path": $0, "line": ""] }
            return (200, ["path": path, "outgoing": [], "backlinks": backlinks], [:])
        case ("DELETE", "file"):
            guard let file = state.files[path] else {
                return (404, ["error": "not_found", "message": "No such file"], [:])
            }
            guard file.version == request.query["base"] else {
                return (409, ["error": "conflict", "message": "Changed", "current": ["path": path, "version": file.version]], [:])
            }
            state.files[path] = nil
            state.treeCounter += 1
            return (200, ["path": path, "deleted": true, "trash": !file.isNote], [:])
        default:
            return (404, ["error": "not_found", "message": "Unknown endpoint"], [:])
        }
    }
    
    private static func save(_ body: [String: Any], _ state: inout State) -> (Int, Any, [String: String]) {
        guard let path = body["path"] as? String, let content = body["content"] as? String, body.keys.contains("base_version") else {
            return (400, ["error": "bad_path", "message": "Missing fields"], [:])
        }
        let base = body["base_version"] as? String
        switch (state.files[path], base) {
        case (nil, nil):
            return saved(&state, path, content, status: 201, merged: nil)
        case (nil, .some):
            return (409, ["error": "deleted", "message": "Deleted meanwhile"], [:])
        case (.some(let file), nil):
            return (409, ["error": "exists", "message": "Already there", "current": ["path": path, "version": file.version, "content": file.content]], [:])
        case (.some(let file), .some(let base)) where file.version == base:
            return saved(&state, path, content, status: 200, merged: nil)
        case (.some(let file), .some):
            if let merged = state.merge?(file.content, content) {
                return saved(&state, path, merged, status: 200, merged: merged)
            }
            return (409, ["error": "conflict", "message": "Same lines edited", "current": ["path": path, "version": file.version, "content": file.content]], [:])
        }
    }
    
    private static func store(_ state: inout State, _ path: String, _ content: String, isNote: Bool) -> String {
        state.versionCounter += 1
        state.treeCounter += 1
        let counter = String(state.versionCounter)
        let version = String(repeating: "0", count: 40 - counter.count) + counter
        state.files[path] = StoredFile(version: version, content: content, isNote: isNote)
        return version
    }
    
    private static func saved(_ state: inout State, _ path: String, _ content: String, status: Int, merged: String?) -> (Int, Any, [String: String]) {
        let version = store(&state, path, content, isNote: true)
        var answer: [String: Any] = ["path": path, "version": version, "merged": merged != nil]
        if let merged {
            answer["content"] = merged
        }
        return (status, answer, [:])
    }
}

/// Hands out "token-1", "token-2"… and counts the requests.
actor CountingTokenProvider {
    private(set) var issued = 0
    
    func next() -> NotesOpenIDToken {
        issued += 1
        return NotesOpenIDToken(accessToken: "token-\(issued)", expiresIn: 3600)
    }
}

/// Reverses the bytes: enough to prove the store never writes plain text, on any platform.
struct ReversingCipher: NotesCipher {
    func seal(_ plaintext: Data) throws -> Data {
        Data(plaintext.reversed())
    }
    
    func open(_ sealed: Data) throws -> Data {
        Data(sealed.reversed())
    }
}

func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("artise-notes-tests-\(UUID().uuidString)")
}

/// A clock the test moves by hand.
final class TestClock: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 1_790_000_000))
    
    var now: Date {
        date.withLock { $0 }
    }
    
    func advance(by seconds: TimeInterval) {
        date.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
