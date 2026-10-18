//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import Compound
import SwiftUI

/// Settings → Security: whether two-step verification is on for the person's Artise ID, and Artise ID's own page
/// to change it (password, passkeys, second steps). Someone who signs in with Google, Microsoft or Apple is
/// protected by that account instead.
@Observable
final class ArtiseSecurityModel {
    enum Phase: Equatable {
        case loading
        /// No usable Artise ID tokens on this phone: sign in to Artise ID first.
        case needsSignIn
        case loaded(ArtiseIDSecurity)
        case failed
    }
    
    private(set) var phase: Phase = .loading
    private(set) var isWorking = false
    @ObservationIgnored var window: UIWindow?
    @ObservationIgnored private let session = ArtiseIDSession.shared
    
    func load() async {
        switch await session.security() {
        case nil:
            phase = .needsSignIn
        case .success(let security):
            phase = .loaded(security)
        case .failure(let error):
            MXLog.error("Artise ID security settings failed: \(error)")
            phase = .failed
        }
    }
    
    func signIn() {
        guard !isWorking, let window else { return }
        Task {
            isWorking = true
            defer { isWorking = false }
            if case .success = await session.signInOnly(provider: nil, window: window) {
                phase = .loading
                await load()
            }
        }
    }
    
    /// Artise ID's page in the sign-in browser session; the status is read again when it closes.
    func manage() {
        guard !isWorking, let window else { return }
        Task {
            isWorking = true
            defer { isWorking = false }
            guard let url = await session.configuration()?.securityURL else { return }
            await session.openSecurityPage(url, window: window)
            await load()
        }
    }
}

struct ArtiseSecurityScreen: View {
    @State private var model = ArtiseSecurityModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ElementNavigationStack {
            Form {
                content
            }
            .compoundList()
            .navigationTitle(ArtiseWorkspacesL10n.text("screen_artise_security_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionDone) { dismiss() }
                }
            }
            .disabled(model.isWorking)
        }
        .introspect(.window, on: .supportedVersions) { window in
            model.window = window
        }
        .task { await model.load() }
    }
    
    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            Section {
                ListRow(kind: .custom {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                })
            }
        case .needsSignIn:
            Section {
                ListRow(label: .plain(title: ArtiseWorkspacesL10n.text("screen_artise_security_sign_in_title"),
                                      description: ArtiseWorkspacesL10n.text("screen_artise_security_sign_in_description")),
                        kind: .label)
                ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_security_sign_in_action"), icon: \.userProfile),
                        kind: .button(action: model.signIn))
            }
        case .loaded(let security):
            loaded(security)
        case .failed:
            Section {
                ListRow(label: .plain(title: ArtiseWorkspacesL10n.text("screen_artise_security_error")), kind: .label)
                ListRow(label: .default(title: L10n.actionRetry, icon: \.restart),
                        kind: .button { Task { await model.load() } })
            }
        }
    }
    
    @ViewBuilder
    private func loaded(_ security: ArtiseIDSecurity) -> some View {
        if let provider = security.provider {
            Section {
                ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_security_provider_\(provider.rawValue)"),
                                        description: ArtiseWorkspacesL10n.text("screen_artise_security_provider_description"),
                                        icon: \.verified),
                        kind: .label)
            }
        } else {
            Section {
                ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_security_two_step"), icon: \.verified),
                        details: .title(ArtiseWorkspacesL10n.text(security.twoStep ? "screen_artise_security_on" : "screen_artise_security_off")),
                        kind: .label)
            } footer: {
                Text(ArtiseWorkspacesL10n.text(security.twoStep ? "screen_artise_security_on_description" : "screen_artise_security_off_description"))
                    .compoundListSectionFooter()
            }
            Section {
                ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_security_manage"), icon: \.settings),
                        kind: .button(action: model.manage))
            } footer: {
                Text(ArtiseWorkspacesL10n.text("screen_artise_security_manage_description"))
                    .compoundListSectionFooter()
            }
        }
    }
}
