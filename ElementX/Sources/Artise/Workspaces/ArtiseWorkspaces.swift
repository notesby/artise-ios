//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseCore
import ArtiseWorkspaces
import Combine
import SwiftUI

/// The workspace the app signs in to and shows: its look, its push gateway, and invite links to it.
///
/// One app serves every company. "Your workspace" finds the workspace, sign-in shows its name and logo, and the
/// signed-in account keeps its workspace's look, read again from its workspace file whenever the app opens.
@MainActor @Observable
final class ArtiseWorkspaces {
    static let shared = ArtiseWorkspaces()
    
    /// Artise's own colour, used when a workspace's accent is missing or invalid.
    static let artiseAccent = Color(red: 0x22 / 255, green: 0x40 / 255, blue: 0x8A / 255)
    
    @ObservationIgnored let client = WorkspaceClient()
    @ObservationIgnored private let store = WorkspaceStore()
    @ObservationIgnored private var foregroundObserver: AnyCancellable?
    @ObservationIgnored private let inviteSubject = PassthroughSubject<String, Never>()
    
    /// The signed-in account's workspace.
    private(set) var current: ResolvedWorkspace?
    /// Whether this workspace's server lets the phone sign in a new one with a QR code (Settings → Link new device).
    private(set) var canLinkNewDevice = false
    /// The workspace picked in "Your workspace", shown on the sign-in screen.
    private(set) var signingIn: ResolvedWorkspace?
    /// A workspace to sign in to after an invite link's join page closed, until "Your workspace" takes it.
    @ObservationIgnored private var pendingInviteAddress: String?
    /// The signed-in session, to restart notes when the workspace's notes API changes.
    @ObservationIgnored private var userSession: UserSessionProtocol?
    
    var branding: WorkspaceBranding? {
        current?.branding
    }
    
    /// The account's notes API; `nil` when its workspace has no web app, and notes are hidden.
    var notesAPIURL: URL? {
        WorkspaceLinks.links(for: current)?.notesAPI
    }
    
    /// The workspace's accent, or `nil` to keep Artise's look.
    var accent: Color? {
        branding?.accentHex.flatMap(Color.init(artiseHex:))
    }
    
    /// What "Your workspace" shows first: the last workspace used.
    var lastAddress: String? {
        store.lastAddress
    }
    
    /// Invite links that finished on their join page while "Your workspace" is open.
    var inviteAddresses: AnyPublisher<String, Never> {
        inviteSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Signing in
    
    /// Someone picked a workspace in "Your workspace": remember it, and greet them once they're in.
    func didChoose(_ workspace: ResolvedWorkspace, address: WorkspaceAddress) {
        store.lastAddress = address.text
        store.save(workspace)
        store.markWelcomePending(serverName: workspace.serverName)
        signingIn = workspace
    }
    
    /// The sign-in screen's workspace, when it's the server being signed in to.
    func signingIn(serverName: String) -> ResolvedWorkspace? {
        signingIn?.serverName == serverName.lowercased() ? signingIn : nil
    }
    
    /// The address an invite link left for "Your workspace" to sign in to; given once.
    func takePendingInviteAddress() -> String? {
        defer { pendingInviteAddress = nil }
        return pendingInviteAddress
    }
    
    // MARK: - The signed-in account
    
    /// Called when an account's session is ready, and with `nil` when it's gone.
    func configure(with userSession: UserSessionProtocol?) {
        self.userSession = userSession
        canLinkNewDevice = false
        guard let userSession, let serverName = WorkspaceHosts.serverName(userID: userSession.clientProxy.userID) else {
            current = nil
            foregroundObserver = nil
            return
        }
        current = store.workspace(serverName: serverName)
            ?? ResolvedWorkspace(slug: nil, serverName: serverName, directoryName: nil, file: nil)
        signingIn = nil
        foregroundObserver = NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.refresh()
                    await self?.checkAppVersion()
                }
            }
        if let homeserverURL = current?.file?.homeserverURL ?? URL(string: userSession.clientProxy.homeserver) {
            Task {
                let supported = await client.supportsQRSignIn(homeserverURL: homeserverURL)
                if self.userSession?.clientProxy.userID == userSession.clientProxy.userID {
                    canLinkNewDevice = supported
                }
            }
        }
        Task {
            await refresh()
            // Also makes Settings → Security show once Artise ID's answer is known.
            await checkAppVersion()
            _ = await ArtiseIDSession.shared.hasTokens()
            if store.consumeWelcome(serverName: serverName) {
                ArtiseWorkspaceWelcome.showIfNeeded(for: current)
            }
        }
    }
    
    /// Any signed-in account's workspace, as remembered on this phone (the workspace switcher's names and logos).
    func workspace(userID: String) -> ResolvedWorkspace? {
        WorkspaceHosts.serverName(userID: userID).flatMap(store.workspace(serverName:))
    }
    
    /// The account signed out: forget its workspace's look on this phone, and Artise ID with the last workspace.
    func signOut(userID: String, isLastAccount: Bool) {
        if let serverName = WorkspaceHosts.serverName(userID: userID) {
            store.remove(serverName: serverName)
        }
        ArtiseNotificationHoursScreen.store.remove(userID: userID)
        ArtiseChatSounds.removeAll(userID: userID)
        if self.userID == userID {
            current = nil
            userSession = nil
            foregroundObserver = nil
        }
        // The other workspaces still use Artise ID to add one again from its list.
        if isLastAccount {
            ArtiseIDSession.shared.forget()
        }
    }
    
    /// The signed-in account, for settings kept per workspace (quiet hours).
    var userID: String? {
        userSession?.clientProxy.userID
    }
    
    /// "Prueba MAS isn't answering. Your messages will go out when it's back."; `nil` without a workspace name.
    var unreachableText: String? {
        current?.displayName.map { String(format: ArtiseWorkspacesL10n.text("screen_artise_workspace_unreachable"), $0) }
    }
    
    // MARK: - Ari and help
    
    /// Ari's chat, opened from the pinned row: the direct chat when there is one, else Ari's profile (with "Message").
    /// `nil` when the workspace doesn't name Ari's account.
    func assistantChatURL() -> URL? {
        guard let userID = branding?.assistantUserID, let userSession else { return nil }
        if case .success(let roomID?) = userSession.clientProxy.directRoomForUserID(userID) {
            return Self.matrixToURL(roomID)
        }
        return Self.matrixToURL(userID)
    }
    
    /// The workspace's admin to write to for help; `nil` without one, or when it's the person themselves.
    var contactURL: URL? {
        guard let userID = branding?.contactUserID, userID != userSession?.clientProxy.userID else { return nil }
        return Self.matrixToURL(userID)
    }
    
    var helpURL: URL? {
        WorkspaceLinks.links(for: current)?.help
    }
    
    /// A permalink the app opens itself (a chat or a profile).
    private static func matrixToURL(_ id: String) -> URL? {
        URL(string: "https://matrix.to/#/\(id)")
    }
    
    /// "Update Artise" when Artise ID or this workspace needs a newer app.
    func checkAppVersion() async {
        let configuration = await ArtiseIDSession.shared.configuration()
        let branding = current?.branding
        ArtiseUpdateNotice.check([configuration?.minimumAppVersion, branding?.minimumAppVersion],
                                 storeLink: branding?.storeLinks?.ios ?? configuration?.storeLinks?.ios,
                                 workspaceName: current?.displayName)
    }
    
    /// Reads the workspace file again; admins change it any time with `!workspace`. When the push gateway
    /// changed, the phone registers again, so the pusher moves to the new address.
    func refresh() async {
        guard let workspace = current else { return }
        guard let file = await client.file(serverName: workspace.serverName), current?.serverName == workspace.serverName else { return }
        let updated = ResolvedWorkspace(slug: workspace.slug, serverName: workspace.serverName, directoryName: workspace.directoryName, file: file)
        guard updated != current else { return }
        let pushChanged = WorkspaceBranding.pushGatewayURL(for: updated.branding) != WorkspaceBranding.pushGatewayURL(for: workspace.branding)
        let notesChanged = WorkspaceLinks.links(for: updated)?.notesAPI != WorkspaceLinks.links(for: workspace)?.notesAPI
        current = updated
        store.save(updated)
        if pushChanged {
            UIApplication.shared.registerForRemoteNotifications()
        }
        if notesChanged {
            ArtiseNotes.shared.configure(with: userSession)
        }
    }
    
    /// The push gateway the account's workspace names; `nil` for the app's default, Artise's shared gateway
    /// (`ArtiseConfiguration.pushGatewayBaseURL`, set by `ArtiseAppSettingsHook`).
    func pushGatewayURL(userID: String) -> URL? {
        WorkspaceHosts.serverName(userID: userID).flatMap(store.workspace(serverName:))?.branding?.pushGatewayURL
    }
    
    /// Settings → Delete account, on the account's own workspace; `nil` when it has no web app, and the row is hidden.
    func accountDeletionURL(language: String?) -> URL? {
        WorkspaceLinks.links(for: current)?.deleteAccount.map { ArtiseAccountDeletion.pageURL($0, language: language) }
    }
    
    // MARK: - Invite links
    
    /// Opens `https://join.artise.co/{slug}/{code}`: the workspace's join page in the app, then sign-in to it, next to
    /// any workspace already open. Returns `false` for other links. `userIDs` are the accounts signed in on this phone,
    /// `showAccount` shows one's chats, and `showSignIn` opens "Your workspace" (adding a
    /// workspace when one is open).
    func handleURL(_ url: URL,
                   userIDs: @escaping () -> [String],
                   showAccount: @escaping (String) -> Void,
                   showSignIn: @escaping () -> Void) -> Bool {
        guard let invite = InviteLink(url: url) else { return false }
        MXLog.info("Opening an invite link to \(invite.slug)")
        Task {
            switch await client.lookup(slug: invite.slug) {
            case .found(let workspace):
                if let userID = Self.userID(in: userIDs(), serverName: workspace.serverName) {
                    // Already in it on this phone: its chats, and a word when they're on screen already.
                    if workspace.serverName == current?.serverName {
                        ArtiseWorkspacePresenter.alert(String(format: ArtiseWorkspacesL10n.text("screen_workspace_invite_already_member"), workspace.name))
                    } else {
                        showAccount(userID)
                    }
                } else {
                    await join(invite, workspace: workspace, showSignIn: showSignIn)
                }
            case .suspended:
                ArtiseWorkspacePresenter.alert(ArtiseWorkspacesL10n.text("screen_workspace_error_paused"))
            case .notFound:
                ArtiseWorkspacePresenter.alert(ArtiseWorkspacesL10n.text("screen_workspace_invite_error_expired"))
            case .rateLimited:
                ArtiseWorkspacePresenter.alert(ArtiseWorkspacesL10n.text("screen_workspace_error_rate_limited"))
            case .unreachable:
                ArtiseWorkspacePresenter.alert(ArtiseWorkspacesL10n.text("screen_workspace_invite_error_unreachable"))
            }
        }
        return true
    }
    
    /// Signed in to Artise ID on this phone: joins with it, then sign-in to the workspace (Continue with Artise) finds
    /// the account. Otherwise, or when the workspace's server can't join from the app, the join page.
    private func join(_ invite: InviteLink, workspace: WorkspaceInfo, showSignIn: @escaping () -> Void) async {
        let joined = await ArtiseIDSession.shared.join(invite, workspace: workspace, using: client)
        MXLog.info("Joining \(invite.slug) from the app: \(joined.map { "\($0)" } ?? "no Artise ID session")")
        switch joined {
        case .joined:
            inviteFinished(slug: invite.slug, showSignIn: showSignIn)
        case .emailUnverified:
            ArtiseWorkspacePresenter.alert(ArtiseWorkspacesL10n.text("screen_workspace_invite_email_unverified"))
        case .inviteExpired:
            ArtiseWorkspacePresenter.alert(ArtiseWorkspacesL10n.text("screen_workspace_invite_error_expired"))
        case .slow:
            ArtiseWorkspacePresenter.alert(ArtiseWorkspacesL10n.text("screen_workspace_error_rate_limited"))
        case .unreachable:
            ArtiseWorkspacePresenter.alert(ArtiseWorkspacesL10n.text("screen_workspace_invite_error_unreachable"))
        case .notOffered, .tokenRefused, nil:
            ArtiseWorkspacePresenter.openInBrowser(invite.joinPageURL(for: workspace)) { [weak self] in
                self?.inviteFinished(slug: invite.slug, showSignIn: showSignIn)
            }
        }
    }
    
    /// The account among `userIDs` that's signed in to `serverName`, if any.
    static func userID(in userIDs: [String], serverName: String) -> String? {
        userIDs.first { WorkspaceHosts.serverName(userID: $0) == serverName.lowercased() }
    }
    
    private func inviteFinished(slug: String, showSignIn: () -> Void) {
        store.lastAddress = slug
        pendingInviteAddress = slug
        inviteSubject.send(slug)
        showSignIn()
    }
}

enum ArtiseWorkspacesL10n {
    /// The phone's language when it's English, Spanish or Portuguese (pt-BR too); Spanish otherwise.
    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "ArtiseWorkspaces", bundle: bundle, comment: "")
    }
    
    /// The text in one of the app's languages ("en", "es", "pt"), for tests.
    static func text(_ key: String, language: String) -> String {
        NSLocalizedString(key, tableName: "ArtiseWorkspaces", bundle: bundle(for: language), comment: "")
    }
    
    private static let bundle: Bundle = {
        let preferred = Bundle.main.preferredLocalizations.first.map { String($0.prefix(2)) }
        let language = ["en", "es", "pt"].contains(preferred) ? preferred ?? "es" : "es"
        return bundle(for: language)
    }()
    
    private static func bundle(for language: String) -> Bundle {
        Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

extension Color {
    /// A colour from `#RRGGBB`; `nil` for anything else.
    init?(artiseHex hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
