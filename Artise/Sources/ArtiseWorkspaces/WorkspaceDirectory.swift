//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import Foundation

/// A workspace as Artise's directory describes it (`GET https://api.artise.co/v1/workspaces/{slug}`).
public struct WorkspaceInfo: Codable, Equatable, Sendable {
    public let slug: String
    public let name: String
    /// Not always `<slug>.artise.co`: the "artise" workspace is `artise.co`.
    public let serverName: String
    public let homeserverURL: URL?
    public let isActive: Bool
    /// The join page that invite links open (`{join_url}/{code}`); servers before invite links don't send it.
    public let joinURL: URL?
    
    public init(slug: String, name: String, serverName: String, homeserverURL: URL?, isActive: Bool, joinURL: URL?) {
        self.slug = slug
        self.name = name
        self.serverName = serverName
        self.homeserverURL = homeserverURL
        self.isActive = isActive
        self.joinURL = joinURL
    }
}

/// The directory's answer to a lookup.
public enum WorkspaceLookupResult: Equatable, Sendable {
    case found(WorkspaceInfo)
    /// Paused by Artise: nobody signs in until its admin sorts it out.
    case suspended(WorkspaceInfo)
    /// Unknown, being set up or closed: the directory doesn't tell them apart.
    case notFound
    /// Too many lookups from this address (30 a minute).
    case rateLimited(retryAfter: TimeInterval?)
    /// No answer, or one the app can't read.
    case unreachable
}

/// Artise's workspace directory.
public enum WorkspaceDirectory {
    public static let baseURL = URL(staticString: "https://api.artise.co/v1/workspaces")
    
    /// The lookup URL for a valid slug.
    public static func lookupURL(slug: String) -> URL {
        baseURL.appendingPathComponent(slug)
    }
    
    /// Reads the directory's answer.
    public static func result(statusCode: Int, retryAfter: String?, body: Data) -> WorkspaceLookupResult {
        switch statusCode {
        case 200:
            guard let info = info(from: body) else { return .unreachable }
            return info.isActive ? .found(info) : .suspended(info)
        case 404:
            return .notFound
        case 429:
            return .rateLimited(retryAfter: retryAfter.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) })
        default:
            return .unreachable
        }
    }
    
    private struct Response: Decodable {
        let slug: String
        let name: String?
        let serverName: String
        let homeserverURL: String?
        let status: String
        let joinURL: String?
        
        enum CodingKeys: String, CodingKey {
            case slug, name, status
            case serverName = "server_name"
            case homeserverURL = "homeserver_url"
            case joinURL = "join_url"
        }
    }
    
    private static func info(from body: Data) -> WorkspaceInfo? {
        guard let response = try? JSONDecoder().decode(Response.self, from: body),
              !response.serverName.isEmpty else {
            return nil
        }
        let name = response.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only "active" signs in: a status the app doesn't know yet is treated like a pause, never as open.
        return WorkspaceInfo(slug: response.slug,
                             name: name?.isEmpty == false ? name ?? response.slug : response.slug,
                             serverName: response.serverName.lowercased(),
                             homeserverURL: response.homeserverURL.flatMap(WorkspaceURL.https),
                             isActive: response.status == "active",
                             joinURL: response.joinURL.flatMap(WorkspaceURL.https))
    }
}

/// HTTP caching hints the server sends (`Cache-Control: max-age=300`).
public enum CacheControl {
    /// How long an answer may be kept; `nil` without a usable `max-age` (or with `no-store`/`no-cache`).
    public static func maxAge(_ header: String?) -> TimeInterval? {
        guard let header else { return nil }
        var maxAge: TimeInterval?
        for directive in header.lowercased().split(separator: ",") {
            let parts = directive.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            switch parts.first {
            case "no-store", "no-cache":
                return nil
            case "max-age" where parts.count == 2:
                maxAge = TimeInterval(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" ")))
            default:
                break
            }
        }
        return maxAge.map { max(0, $0) }
    }
}

enum WorkspaceURL {
    /// An `https` URL with a host, or `nil`: the apps never follow other schemes from server data.
    static func https(_ string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespaces)),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}
