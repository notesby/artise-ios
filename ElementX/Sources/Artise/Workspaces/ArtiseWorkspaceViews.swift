//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import Compound
import SwiftUI

/// A workspace's logo, or nothing when it has none (or it can't load).
struct ArtiseWorkspaceLogo: View {
    let url: URL?
    let size: CGFloat
    
    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size / 5))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

/// The signed-in workspace's logo in the home top bar.
struct ArtiseHomeWorkspaceLogo: View {
    private let workspaces = ArtiseWorkspaces.shared
    
    var body: some View {
        ArtiseWorkspaceLogo(url: workspaces.branding?.logoURL, size: 28)
    }
}

/// The home screen's title: the workspace's name, else "Chats".
enum ArtiseHomeTitle {
    @MainActor
    static func text(default defaultTitle: String) -> String {
        ArtiseWorkspaces.shared.branding?.name ?? defaultTitle
    }
}

/// The top of the sign-in screen: the workspace's logo and "Sign in to <name>", else the lock and the server.
struct ArtiseWorkspaceLoginHeader: View {
    let serverName: String
    
    private let workspaces = ArtiseWorkspaces.shared
    
    var body: some View {
        let workspace = workspaces.signingIn(serverName: serverName)
        VStack(spacing: 8) {
            if let logoURL = workspace?.branding?.logoURL {
                ArtiseWorkspaceLogo(url: logoURL, size: 64)
                    .padding(.bottom, 8)
            } else {
                BigIcon(icon: \.lockSolid)
                    .padding(.bottom, 8)
            }
            
            Text(L10n.screenLoginTitleWithHomeserver(workspace?.displayName ?? serverName))
                .font(.compound.headingMDBold)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textPrimary)
        }
        .padding(.horizontal, 16)
    }
}

/// A full-width button in the workspace's accent with white text (the server only accepts accents dark enough
/// for it); Compound's primary button when the workspace has none.
struct ArtiseAccentButton: View {
    let title: String
    let accent: Color?
    let action: () -> Void
    
    var body: some View {
        if let accent {
            Button(action: action) {
                Text(title)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button(title, action: action)
                .buttonStyle(.compound(.primary))
        }
    }
}

extension View {
    /// Tints an Artise screen with the signed-in workspace's accent, when it has one.
    func artiseWorkspaceAccent() -> some View {
        modifier(ArtiseWorkspaceAccentModifier())
    }
}

private struct ArtiseWorkspaceAccentModifier: ViewModifier {
    private let workspaces = ArtiseWorkspaces.shared
    
    func body(content: Content) -> some View {
        if let accent = workspaces.accent {
            content.tint(accent)
        } else {
            content
        }
    }
}

/// The welcome after the first sign-in to a workspace: its logo, name and welcome line.
struct ArtiseWorkspaceWelcome: View {
    let workspace: ResolvedWorkspace
    let text: String
    let accent: Color?
    let onDone: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)
            ArtiseWorkspaceLogo(url: workspace.branding?.logoURL, size: 88)
            if let name = workspace.displayName {
                Text(name)
                    .font(.compound.headingLGBold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
            }
            Text(text)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 24)
            ArtiseAccentButton(title: ArtiseWorkspacesL10n.text("screen_workspace_welcome_action"), accent: accent, action: onDone)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
    }
    
    /// Shows the workspace's welcome line in the phone's language (else the workspace's), if it has one.
    @MainActor
    static func showIfNeeded(for workspace: ResolvedWorkspace?) {
        guard let workspace,
              let text = workspace.branding?.welcomeText(preferredLanguages: Array(Locale.preferredLanguages.prefix(1))) else {
            return
        }
        // After home has appeared, so the sheet doesn't land on a screen that's about to go.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            weak var host: UIViewController?
            let welcome = ArtiseWorkspaceWelcome(workspace: workspace, text: text, accent: ArtiseWorkspaces.shared.accent) {
                host?.dismiss(animated: true)
            }
            host = ArtiseWorkspacePresenter.present(welcome)
        }
    }
}
