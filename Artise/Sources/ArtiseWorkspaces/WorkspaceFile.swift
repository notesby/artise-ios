//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import Foundation

/// A workspace's `https://{server_name}/.well-known/matrix/client`: where its server is, and how it looks in the app.
public struct WorkspaceFile: Codable, Equatable, Sendable {
    /// `m.homeserver.base_url`.
    public let homeserverURL: URL?
    /// Artise's `co.artise.workspace` section; `nil` when missing or unreadable (Artise's default look).
    public let branding: WorkspaceBranding?
    
    public init(homeserverURL: URL?, branding: WorkspaceBranding?) {
        self.homeserverURL = homeserverURL
        self.branding = branding
    }
    
    /// Reads the file; `nil` when it isn't a JSON object. Fields the app doesn't know are ignored.
    public static func parse(_ data: Data) -> WorkspaceFile? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let homeserver = (object["m.homeserver"] as? [String: Any])?["base_url"] as? String
        return WorkspaceFile(homeserverURL: homeserver.flatMap(WorkspaceURL.https),
                             branding: (object["co.artise.workspace"] as? [String: Any]).flatMap(WorkspaceBranding.init(section:)))
    }
}

/// How a workspace presents itself. Every field is optional: what's missing or invalid falls back to Artise's look.
public struct WorkspaceBranding: Codable, Equatable, Sendable {
    public static let defaultPushGatewayURL = URL(staticString: "https://push.artise.co/_matrix/push/v1/notify")
    
    public var name: String?
    /// A square PNG with transparent padding.
    public var logoURL: URL?
    /// `#RRGGBB`, upper case.
    public var accentHex: String?
    public var assistantName: String?
    /// Welcome lines by language (`en`, `es`, `pt`).
    public var welcome: [String: String]
    /// The workspace's default language.
    public var language: String?
    /// The features switched on; `nil` when the server doesn't say, so nothing is hidden.
    public var features: Set<String>?
    public var pushGatewayURL: URL?
    /// The workspace's web app; `nil` when its server has none.
    public var links: WorkspaceLinks?
    /// The workspace's own Artise app client for its sign-in service; `nil` on workspaces without it.
    public var oauth: WorkspaceOAuthClient?
    /// Ari's account, whose chat is pinned.
    public var assistantUserID: String?
    /// The person to write to for help: the workspace's first admin.
    public var contactUserID: String?
    public var minimumAppVersion: MinimumAppVersion?
    public var storeLinks: StoreLinks?
    /// The charts' series colours an admin set (`colors.palette`, up to 8, `#RRGGBB`); `nil` when unset, so charts use
    /// the accent and the server's own palette.
    public var chartPalette: [String]?
    
    public init(name: String? = nil, logoURL: URL? = nil, accentHex: String? = nil, assistantName: String? = nil,
                welcome: [String: String] = [:], language: String? = nil, features: Set<String>? = nil, pushGatewayURL: URL? = nil,
                links: WorkspaceLinks? = nil, oauth: WorkspaceOAuthClient? = nil, assistantUserID: String? = nil,
                contactUserID: String? = nil, minimumAppVersion: MinimumAppVersion? = nil, storeLinks: StoreLinks? = nil,
                chartPalette: [String]? = nil) {
        self.name = name
        self.logoURL = logoURL
        self.accentHex = accentHex
        self.assistantName = assistantName
        self.welcome = welcome
        self.language = language
        self.features = features
        self.pushGatewayURL = pushGatewayURL
        self.links = links
        self.oauth = oauth
        self.assistantUserID = assistantUserID
        self.contactUserID = contactUserID
        self.minimumAppVersion = minimumAppVersion
        self.storeLinks = storeLinks
        self.chartPalette = chartPalette
    }
    
    /// Reads the section field by field, so one bad value doesn't lose the others. Any `version` is read:
    /// a newer one only adds fields.
    init?(section: [String: Any]) {
        self.init(name: Self.text(section["name"], limit: 60),
                  logoURL: (section["logo"] as? String).flatMap(WorkspaceURL.https),
                  accentHex: ((section["colors"] as? [String: Any])?["accent"] as? String).flatMap(Self.hexColor),
                  assistantName: Self.text(section["assistant_name"], limit: 30),
                  welcome: (section["welcome"] as? [String: Any] ?? [:]).reduce(into: [:]) { lines, entry in
                      if let line = Self.text(entry.value, limit: 200) {
                          lines[entry.key.lowercased()] = line
                      }
                  },
                  language: Self.text(section["language"], limit: 10)?.lowercased(),
                  features: (section["features"] as? [Any]).map { Set($0.compactMap { $0 as? String }) },
                  pushGatewayURL: (section["push_gateway"] as? String).flatMap(WorkspaceURL.https),
                  links: (section["links"] as? [String: Any]).flatMap(WorkspaceLinks.init(section:)),
                  oauth: (section["oauth"] as? [String: Any]).flatMap(WorkspaceOAuthClient.init(section:)),
                  assistantUserID: (section["assistant_user_id"] as? String).flatMap(Self.userID),
                  contactUserID: (section["contact_user_id"] as? String).flatMap(Self.userID),
                  minimumAppVersion: MinimumAppVersion(value: section["min_app_version"]),
                  storeLinks: StoreLinks(value: section["store_links"]),
                  chartPalette: Self.palette((section["colors"] as? [String: Any])?["palette"]))
    }
    
    /// Up to 8 valid colours from `colors.palette`; `nil` when there are none.
    static func palette(_ value: Any?) -> [String]? {
        let colors = ((value as? [Any]) ?? []).compactMap { ($0 as? String).flatMap(hexColor) }
        return colors.isEmpty ? nil : Array(colors.prefix(8))
    }
    
    /// Where the pusher is registered: the workspace's gateway, else Artise's shared one.
    public static func pushGatewayURL(for branding: WorkspaceBranding?) -> URL {
        branding?.pushGatewayURL ?? defaultPushGatewayURL
    }
    
    /// The welcome line in the phone's language, else in the workspace's language; `nil` when there's neither.
    public func welcomeText(preferredLanguages: [String]) -> String? {
        let languages = preferredLanguages.map { String($0.lowercased().prefix(while: { $0 != "-" && $0 != "_" })) }
        for language in languages + [language].compactMap(\.self) {
            if let text = welcome[language] {
                return text
            }
        }
        return nil
    }
    
    /// Whether an Artise screen whose server feature is `name` shows. Only call it with names the app knows:
    /// a screen is hidden only when the server lists its features and this one isn't there.
    public func shows(feature name: String) -> Bool {
        features?.contains(name) ?? true
    }
    
    /// `#RRGGBB`, with or without the `#`; anything else is ignored.
    static func hexColor(_ value: String) -> String? {
        let hex = value.trimmingCharacters(in: .whitespaces).uppercased()
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits
    }
    
    /// `@name:server`, without spaces; anything else is ignored.
    static func userID(_ value: String) -> String? {
        let parts = value.split(separator: ":", maxSplits: 1)
        guard value.hasPrefix("@"), value.count <= 255, parts.count == 2, parts[0].count > 1, !parts[1].isEmpty,
              !value.contains(where: \.isWhitespace) else {
            return nil
        }
        return value
    }
    
    private static func text(_ value: Any?, limit: Int) -> String? {
        guard let value = value as? String else { return nil }
        let text = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : String(text.prefix(limit))
    }
}

public extension WorkspaceBranding {
    /// Text written for Artise's assistant ("Ari") with the workspace's assistant name instead.
    /// Only the whole word changes, so "Arizona" stays as it is.
    func naming(_ text: String) -> String {
        guard let assistantName, assistantName != "Ari" else { return text }
        return text.replacing(/\bAri\b/, with: assistantName)
    }
}

/// A workspace's web app (`links`): full URLs from the server, never built from its server name, as each server
/// sets its own web host.
public struct WorkspaceLinks: Codable, Equatable, Sendable {
    public var web: URL?
    /// The notes API base; the API's paths are relative to it.
    public var notesAPI: URL?
    /// Settings → Delete account.
    public var deleteAccount: URL?
    /// Settings → Help.
    public var help: URL?
    
    public init(web: URL? = nil, notesAPI: URL? = nil, deleteAccount: URL? = nil, help: URL? = nil) {
        self.web = web
        self.notesAPI = notesAPI
        self.deleteAccount = deleteAccount
        self.help = help
    }
    
    init?(section: [String: Any]) {
        self.init(web: (section["web"] as? String).flatMap(WorkspaceURL.https),
                  notesAPI: (section["notes_api"] as? String).flatMap(WorkspaceURL.https),
                  deleteAccount: (section["delete_account"] as? String).flatMap(WorkspaceURL.https),
                  help: (section["help"] as? String).flatMap(WorkspaceURL.https))
        if self == WorkspaceLinks() {
            return nil
        }
    }
    
    /// The workspace's links. Without them its notes, help and delete page are hidden.
    public static func links(for workspace: ResolvedWorkspace?) -> WorkspaceLinks? {
        workspace?.branding?.links
    }
}
