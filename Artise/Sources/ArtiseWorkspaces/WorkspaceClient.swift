//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends requests. A seam, so tests can answer without a network.
public protocol WorkspaceHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public extension WorkspaceHTTPTransport {
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }
}

/// `URLSession` as a transport, without cookies or a shared cache: the client keeps its own, as the server asks.
public struct URLSessionWorkspaceTransport: WorkspaceHTTPTransport {
    private let session: URLSession
    
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
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

/// A workspace ready to sign in to.
public struct ResolvedWorkspace: Codable, Equatable, Sendable {
    /// `nil` when someone typed a server name.
    public let slug: String?
    public let serverName: String
    /// The name the directory gave, used until the workspace file has one.
    public let directoryName: String?
    /// `nil` when the file couldn't be read: sign-in still goes ahead, with Artise's look.
    public let file: WorkspaceFile?
    
    public init(slug: String?, serverName: String, directoryName: String?, file: WorkspaceFile?) {
        self.slug = slug
        self.serverName = serverName
        self.directoryName = directoryName
        self.file = file
    }
    
    public var branding: WorkspaceBranding? {
        file?.branding
    }
    
    public var displayName: String? {
        branding?.name ?? directoryName
    }
}

/// What came of looking up what someone typed.
public enum WorkspaceResolution: Equatable, Sendable {
    case ready(ResolvedWorkspace)
    case notFound(slug: String)
    case paused(name: String)
    case rateLimited
    /// No network, or the directory didn't answer: never silently replaced by another server.
    case unreachable
}

/// Finds workspaces and reads their workspace files, keeping each answer as long as the server allows.
public actor WorkspaceClient {
    private struct Cached<Value> {
        let value: Value
        let expiry: Date
    }
    
    private let transport: WorkspaceHTTPTransport
    private let now: @Sendable () -> Date
    private var lookups: [String: Cached<WorkspaceLookupResult>] = [:]
    private var files: [String: Cached<WorkspaceFile?>] = [:]
    
    public init(transport: WorkspaceHTTPTransport = URLSessionWorkspaceTransport(), now: @escaping @Sendable () -> Date = { .now }) {
        self.transport = transport
        self.now = now
    }
    
    /// Looks up a workspace name, or takes a server name as it is, and reads the workspace's file.
    public func resolve(_ address: WorkspaceAddress) async -> WorkspaceResolution {
        switch address {
        case .serverName(let serverName):
            return await .ready(ResolvedWorkspace(slug: nil, serverName: serverName, directoryName: nil, file: file(serverName: serverName)))
        case .slug(let slug):
            switch await lookup(slug: slug) {
            case .found(let info):
                return await .ready(ResolvedWorkspace(slug: info.slug, serverName: info.serverName, directoryName: info.name,
                                                      file: file(serverName: info.serverName)))
            case .suspended(let info):
                return .paused(name: info.name)
            case .notFound:
                return .notFound(slug: slug)
            case .rateLimited:
                return .rateLimited
            case .unreachable:
                return .unreachable
            }
        }
    }
    
    /// The directory's answer for a valid slug.
    public func lookup(slug: String) async -> WorkspaceLookupResult {
        if let cached = lookups[slug], cached.expiry > now() {
            return cached.value
        }
        do {
            let (body, response) = try await transport.get(WorkspaceDirectory.lookupURL(slug: slug))
            let result = WorkspaceDirectory.result(statusCode: response.statusCode,
                                                   retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                                                   body: body)
            if case .found = result, let maxAge = CacheControl.maxAge(response.value(forHTTPHeaderField: "Cache-Control")) {
                lookups[slug] = Cached(value: result, expiry: now().addingTimeInterval(maxAge))
            }
            return result
        } catch {
            return .unreachable
        }
    }
    
    /// The workspace file, or `nil` when it can't be read. Never a reason to stop signing in.
    public func file(serverName: String) async -> WorkspaceFile? {
        if let cached = files[serverName], cached.expiry > now() {
            return cached.value
        }
        guard let url = URL(string: "https://\(serverName)/.well-known/matrix/client") else { return nil }
        guard let (body, response) = try? await transport.get(url), response.statusCode == 200 else { return nil }
        let file = WorkspaceFile.parse(body)
        if let maxAge = CacheControl.maxAge(response.value(forHTTPHeaderField: "Cache-Control")) {
            files[serverName] = Cached(value: file, expiry: now().addingTimeInterval(maxAge))
        }
        return file
    }
    
    /// A 200 answer's body, or `nil`.
    func answer(_ url: URL) async -> Data? {
        guard let (body, response) = try? await transport.get(url), response.statusCode == 200 else { return nil }
        return body
    }
}
