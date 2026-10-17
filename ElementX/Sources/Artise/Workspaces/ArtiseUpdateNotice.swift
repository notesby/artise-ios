//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import Compound
import SwiftUI

/// "Update Artise": covers the app when Artise ID or the workspace needs a newer app (`min_app_version`).
/// It can't be closed; the App Store link opens when the server gives one.
@MainActor
enum ArtiseUpdateNotice {
    private static var host: UIViewController?
    
    /// Shows the notice when any of these minimums is newer than this app, once.
    static func check(_ minimums: [MinimumAppVersion?], storeLink: URL?, workspaceName: String?) {
        let version = InfoPlistReader.main.bundleShortVersionString
        guard host == nil, minimums.contains(where: { $0?.blocks(appVersion: version) == true }) else { return }
        MXLog.info("This app (\(version)) is older than the server needs; asking to update.")
        let notice = ArtiseUpdateNoticeView(workspaceName: workspaceName, storeLink: storeLink)
        guard let presenter = UIViewController.artiseTopViewController() else { return }
        let controller = UIHostingController(rootView: notice)
        controller.modalPresentationStyle = .fullScreen
        controller.isModalInPresentation = true
        presenter.present(controller, animated: true)
        host = controller
    }
}

struct ArtiseUpdateNoticeView: View {
    let workspaceName: String?
    let storeLink: URL?
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            AuthenticationStartLogo(size: 96, hideBrandChrome: false, isOnGradient: false)
            Text(ArtiseWorkspacesL10n.text("screen_artise_update_title"))
                .font(.compound.headingLGBold)
                .foregroundStyle(.compound.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            if let storeLink {
                Button(ArtiseWorkspacesL10n.text("screen_artise_update_action")) { openURL(storeLink) }
                    .buttonStyle(.compound(.primary))
            } else {
                Text(ArtiseWorkspacesL10n.text("screen_artise_update_no_link"))
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
    }
    
    private var message: String {
        guard let workspaceName else { return ArtiseWorkspacesL10n.text("screen_artise_update_message_generic") }
        return String(format: ArtiseWorkspacesL10n.text("screen_artise_update_message"), workspaceName)
    }
}
