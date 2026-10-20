//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends HTTP requests. A seam, so tests can answer without a network.
public protocol NotesHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession` as a transport.
public struct URLSessionNotesTransport: NotesHTTPTransport {
    private let session: URLSession
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
            .resume()
        }
    }
}

/// The answer to a conditional tree request.
public enum TreeResponse: Equatable, Sendable {
    /// `304`: nothing changed since the ETag that was sent.
    case notModified
    case changed(NotesTree, etag: String?)
}

/// The Notes API v1, one function per endpoint (docs/notes-api.md in family-wiki).
///
/// Every call signs in with an OpenID token from the token source. On a `401` it asks for a fresh
/// token and retries once. Tokens and note text are never logged.
public struct NotesAPIClient: Sendable {
    public static let defaultBaseURL = URL(staticString: "https://chat.artise.co/api/notes/v1")
    
    private let baseURL: URL
    private let transport: NotesHTTPTransport
    private let tokenSource: NotesTokenSource
    
    public init(baseURL: URL = Self.defaultBaseURL, transport: NotesHTTPTransport = URLSessionNotesTransport(), tokenSource: NotesTokenSource) {
        self.baseURL = baseURL
        self.transport = transport
        self.tokenSource = tokenSource
    }
    
    // MARK: - Endpoints
    
    public func chats() async throws(NotesError) -> [NotesChat] {
        let dto: ChatsDTO = try await json(request(url(["chats"])))
        return dto.chats.map { NotesChat(roomID: $0.id, name: $0.name, tree: $0.tree) }
    }
    
    /// The chat's file list. With `etag`, `.notModified` when nothing changed.
    public func tree(roomID: String, etag: String?) async throws(NotesError) -> TreeResponse {
        var request = request(url(roomID: roomID, "tree"))
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await send(request)
        if response.statusCode == 304 {
            return .notModified
        }
        let dto: TreeDTO = try decode(data)
        let files = dto.files.map { NotesFile(path: $0.path, version: $0.version, size: $0.size, modified: $0.modified, isNote: $0.note) }
        return .changed(NotesTree(tree: dto.tree, files: files, folders: dto.folders ?? []),
                        etag: response.value(forHTTPHeaderField: "ETag"))
    }
    
    /// A note's text now or, with `atCommit`, as it was at that commit from `history`.
    public func note(roomID: String, path: String, atCommit: String? = nil) async throws(NotesError) -> Note {
        var query = [("path", path)]
        if let atCommit {
            query.append(("at", atCommit))
        }
        let dto: NoteDTO = try await json(request(url(roomID: roomID, "note", query: query)))
        return Note(path: dto.path, version: dto.version, content: dto.content)
    }
    
    /// Saves a note. `baseVersion` is the version the edit started from, or `nil` to create the note.
    /// The server merges edits to different lines; see `SavedNote.merged`.
    public func saveNote(roomID: String, path: String, content: String, baseVersion: String?) async throws(NotesError) -> SavedNote {
        let body = SaveNoteDTO(path: path, content: content, baseVersion: baseVersion)
        let dto: SavedDTO = try await json(request(url(roomID: roomID, "note"), method: "PUT", jsonBody: body))
        return SavedNote(path: dto.path, version: dto.version, merged: dto.merged ?? false, content: dto.content)
    }
    
    /// A raw file's bytes (photos, PDFs…).
    public func raw(roomID: String, path: String) async throws(NotesError) -> Data {
        try await send(request(url(roomID: roomID, "raw", query: [("path", path)]))).0
    }
    
    /// Uploads a raw file; `baseVersion` `nil` creates it. Returns the new version.
    public func saveRaw(roomID: String, path: String, data: Data, contentType: String, baseVersion: String?) async throws(NotesError) -> String {
        var query = [("path", path)]
        if let baseVersion {
            query.append(("base", baseVersion))
        }
        var request = request(url(roomID: roomID, "raw", query: query), method: "PUT")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let dto: SavedDTO = try await json(request)
        return dto.version
    }
    
    public func delete(roomID: String, path: String, baseVersion: String) async throws(NotesError) {
        _ = try await send(request(url(roomID: roomID, "file", query: [("path", path), ("base", baseVersion)]), method: "DELETE"))
    }
    
    public func move(roomID: String, from: String, to: String, baseVersion: String) async throws(NotesError) -> MovedNote {
        let body = MoveDTO(from: from, to: to, baseVersion: baseVersion)
        let dto: MovedDTO = try await json(request(url(roomID: roomID, "move"), method: "POST", jsonBody: body))
        return MovedNote(from: dto.from, to: dto.to, version: dto.version, linksUpdated: dto.linksUpdated ?? [])
    }
    
    /// Creates a folder (and any missing parents).
    public func createFolder(roomID: String, path: String) async throws(NotesError) {
        _ = try await send(request(url(roomID: roomID, "folder"), method: "POST", jsonBody: FolderDTO(path: path)))
    }
    
    /// Moves or renames a folder with everything inside; the server rewrites the links to what moved.
    public func moveFolder(roomID: String, from: String, to: String) async throws(NotesError) -> MovedFolder {
        let body = MoveFolderDTO(from: from, to: to)
        let dto: MovedFolderDTO = try await json(request(url(roomID: roomID, "move"), method: "POST", jsonBody: body))
        return MovedFolder(from: dto.from, to: dto.to,
                           moved: dto.moved.map { MovedNote(from: $0.from, to: $0.to, version: $0.version, linksUpdated: []) },
                           linksUpdated: dto.linksUpdated ?? [])
    }
    
    /// Deletes a folder. One that isn't empty needs `recursive`, or fails with `.notEmpty`.
    public func deleteFolder(roomID: String, path: String, recursive: Bool) async throws(NotesError) -> DeletedFolder {
        var query = [("path", path)]
        if recursive {
            query.append(("recursive", "true"))
        }
        let dto: DeletedFolderDTO = try await json(request(url(roomID: roomID, "folder", query: query), method: "DELETE"))
        return DeletedFolder(path: dto.path, notes: dto.notes ?? 0, files: dto.files ?? 0)
    }
    
    public func search(roomID: String, query: String) async throws(NotesError) -> [NotesSearchResult] {
        let dto: SearchDTO = try await json(request(url(roomID: roomID, "search", query: [("q", query)])))
        return dto.results.map { NotesSearchResult(path: $0.path, lines: $0.lines) }
    }
    
    public func links(roomID: String, path: String) async throws(NotesError) -> NoteLinks {
        let dto: LinksDTO = try await json(request(url(roomID: roomID, "links", query: [("path", path)])))
        return NoteLinks(path: dto.path,
                         outgoing: dto.outgoing.map { .init(target: $0.target, path: $0.path, candidates: $0.candidates ?? []) },
                         backlinks: dto.backlinks.map { .init(path: $0.path, line: $0.line) })
    }
    
    /// The chat's pages: people, places and things with a note of their own, and every photo and document.
    public func pages(roomID: String) async throws(NotesError) -> [NotesPage] {
        let dto: PagesDTO = try await json(request(url(roomID: roomID, "pages")))
        return dto.pages.map {
            NotesPage(path: $0.path, title: $0.title, type: $0.type ?? "", folder: $0.folder ?? "",
                      aliases: $0.aliases ?? [], summary: $0.summary ?? "", isNote: $0.note ?? $0.path.hasSuffix(".md"))
        }
    }
    
    public func graph(roomID: String) async throws(NotesError) -> NotesGraph {
        let dto: GraphDTO = try await json(request(url(roomID: roomID, "graph")))
        let edges = dto.edges.compactMap { $0.count == 2 ? NotesGraph.Edge(from: $0[0], to: $0[1]) : nil }
        return NotesGraph(nodes: dto.nodes, edges: edges)
    }
    
    public func history(roomID: String, path: String) async throws(NotesError) -> [NoteVersion] {
        let dto: HistoryDTO = try await json(request(url(roomID: roomID, "history", query: [("path", path)])))
        return dto.versions.map {
            NoteVersion(commit: $0.commit, at: $0.at, message: $0.message,
                        author: ChangeAuthor(who: $0.who, how: $0.how, detail: $0.detail ?? "", by: $0.by))
        }
    }
    
    /// The chat's latest changes, newest first; `before` is the last commit of the previous page.
    public func changes(roomID: String, before: String?, limit: Int = 50) async throws(NotesError) -> NotesChangesPage {
        var query = [("limit", String(limit))]
        if let before {
            query.append(("before", before))
        }
        let dto: ChangesDTO = try await json(request(url(roomID: roomID, "changes", query: query)))
        let changes = dto.changes.map { change in
            NotesChange(commit: change.commit, at: change.at, message: change.message,
                        author: ChangeAuthor(who: change.who, how: change.how, detail: change.detail ?? "", by: change.by),
                        files: change.files.map { ChangedFile(path: $0.path, change: FileChange(serverValue: $0.change), from: $0.from) })
        }
        return NotesChangesPage(changes: changes, more: dto.more ?? false)
    }
    
    // MARK: - URLs
    
    /// Percent-encodes everything but RFC 3986's unreserved characters, as the contract wants for
    /// room IDs in the path (`!abc:artise.co` → `%21abc%3Aartise.co`) and for query values.
    static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // `alphanumerics` includes non-ASCII letters, which must be encoded too.
        let ascii = CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127))
        return value.addingPercentEncoding(withAllowedCharacters: allowed.intersection(ascii)) ?? value
    }
    
    private func url(_ segments: [String]) -> URL {
        URL(string: baseURL.absoluteString.trimmingSuffix("/") + "/" + segments.joined(separator: "/")) ?? baseURL
    }
    
    func url(roomID: String, _ endpoint: String, query: [(String, String)] = []) -> URL {
        var string = baseURL.absoluteString.trimmingSuffix("/") + "/chats/" + Self.encode(roomID) + "/" + endpoint
        if !query.isEmpty {
            string += "?" + query.map { Self.encode($0.0) + "=" + Self.encode($0.1) }.joined(separator: "&")
        }
        return URL(string: string) ?? baseURL
    }
    
    // MARK: - Sending
    
    private func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    
    private func request(_ url: URL, method: String, jsonBody: some Encodable) -> URLRequest {
        var request = request(url, method: method)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(jsonBody)
        return request
    }
    
    private func json<T: Decodable>(_ request: URLRequest) async throws(NotesError) -> T {
        try await decode(send(request).0)
    }
    
    private func decode<T: Decodable>(_ data: Data) throws(NotesError) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .server(status: 0, message: "Unexpected answer from the notes server: \(error)")
        }
    }
    
    /// Signs the request in, retries once with a fresh token on `401`, and maps failures to `NotesError`.
    private func send(_ request: URLRequest) async throws(NotesError) -> (Data, HTTPURLResponse) {
        let firstToken = try await tokenSource.token()
        if let result = try await attempt(request, token: firstToken, retryOnUnauthorized: true) {
            return result
        }
        await tokenSource.invalidate(firstToken)
        let secondToken = try await tokenSource.token()
        guard let result = try await attempt(request, token: secondToken, retryOnUnauthorized: false) else {
            throw .unauthorized("Signed out")
        }
        return result
    }
    
    /// One try. `nil` means a `401` worth retrying with a new token.
    private func attempt(_ request: URLRequest, token: String, retryOnUnauthorized: Bool) async throws(NotesError) -> (Data, HTTPURLResponse)? {
        var signed = request
        signed.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(signed)
        } catch {
            throw .network(error.localizedDescription)
        }
        switch response.statusCode {
        case 401 where retryOnUnauthorized:
            return nil
        case 200..<300, 304:
            return (data, response)
        default:
            throw Self.error(status: response.statusCode, body: data)
        }
    }
    
    static func error(status: Int, body: Data) -> NotesError {
        let dto = try? JSONDecoder().decode(ErrorDTO.self, from: body)
        let message = dto?.message ?? "HTTP \(status)"
        let current = dto?.current.map { ServerCopy(path: $0.path, version: $0.version, content: $0.content) }
        switch dto?.error {
        case "unauthorized": return .unauthorized(message)
        case "no_chat": return .noChat(message)
        case "bad_path": return .badPath(message)
        case "not_found": return .notFound(message)
        case "exists": return .exists(message, current: current)
        case "conflict": return .conflict(message, current: current)
        case "deleted": return .deleted(message)
        case "too_big": return .tooBig(message)
        case "not_a_note": return .notANote(message)
        case "in_use": return .inUse(message, usedBy: dto?.usedBy ?? [])
        case "not_empty": return .notEmpty(message, files: dto?.files ?? 0, folders: dto?.folders ?? 0)
        default: return status == 401 ? .unauthorized(message) : .server(status: status, message: message)
        }
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
