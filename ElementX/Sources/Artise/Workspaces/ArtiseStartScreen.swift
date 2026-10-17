//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import Combine
import Compound
import SwiftUI

/// The first screen: sign in once with Artise ID (Apple, Google, Microsoft or email) and pick a workspace, so nobody
/// types a workspace name. Without Artise ID (offline, or not offered yet) it's Element's start screen, as before.
final class ArtiseStartScreenCoordinator: CoordinatorProtocol {
    private let parameters: AuthenticationStartScreenParameters
    private let fallback: AuthenticationStartScreenCoordinator
    private let model: ArtiseStartScreenModel
    private let actionsSubject = PassthroughSubject<AuthenticationStartScreenCoordinatorAction, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    var actions: AnyPublisher<AuthenticationStartScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AuthenticationStartScreenParameters) {
        self.parameters = parameters
        fallback = AuthenticationStartScreenCoordinator(parameters: parameters)
        model = ArtiseStartScreenModel(signInStarter: ArtiseWorkspaceSignInStarter(authenticationService: parameters.authenticationService,
                                                                                   authenticationFlow: .login,
                                                                                   appSettings: parameters.appSettings),
                                       userIndicatorController: parameters.userIndicatorController,
                                       usesFallback: parameters.provisioningParameters != nil)
    }
    
    func start() {
        fallback.start()
        fallback.actions.subscribe(actionsSubject).store(in: &cancellables)
        model.actions.subscribe(actionsSubject).store(in: &cancellables)
        model.load()
    }
    
    func stop() {
        parameters.userIndicatorController.retractAllIndicators()
        fallback.stop()
    }
    
    func toPresentable() -> AnyView {
        AnyView(ArtiseStartScreen(model: model, fallback: fallback.toPresentable()))
    }
}

@Observable
final class ArtiseStartScreenModel {
    enum Phase: Equatable {
        case loading
        /// Element's start screen: no Artise ID, or a provisioning link.
        case fallback
        case providers
        case workspaces([ArtiseIDWorkspace])
        case noWorkspaces
    }
    
    private(set) var phase: Phase = .loading
    private(set) var errorMessage: String?
    private(set) var isWorking = false
    @ObservationIgnored var window: UIWindow?
    @ObservationIgnored let actions = PassthroughSubject<AuthenticationStartScreenCoordinatorAction, Never>()
    
    @ObservationIgnored private let signInStarter: ArtiseWorkspaceSignInStarter
    @ObservationIgnored private let userIndicatorController: UserIndicatorControllerProtocol
    @ObservationIgnored private let usesFallback: Bool
    
    init(signInStarter: ArtiseWorkspaceSignInStarter, userIndicatorController: UserIndicatorControllerProtocol, usesFallback: Bool) {
        self.signInStarter = signInStarter
        self.userIndicatorController = userIndicatorController
        self.usesFallback = usesFallback
    }
    
    func load() {
        guard !usesFallback else {
            phase = .fallback
            return
        }
        Task {
            guard let configuration = await ArtiseIDSession.shared.configuration() else {
                phase = .fallback
                return
            }
            ArtiseUpdateNotice.check([configuration.minimumAppVersion], storeLink: configuration.storeLinks?.ios, workspaceName: nil)
            // Signed in to Artise ID earlier but not to a workspace yet: the list again, without a page.
            if case .success(let workspaces) = await ArtiseIDSession.shared.workspacesAgain(), !workspaces.isEmpty {
                phase = .workspaces(workspaces)
            } else {
                phase = .providers
            }
        }
    }
    
    func signIn(with provider: ArtiseIDProvider?) {
        guard !isWorking, let window else { return }
        errorMessage = nil
        Task {
            isWorking = true
            defer { isWorking = false }
            switch await ArtiseIDSession.shared.signIn(provider: provider, window: window) {
            case .success(let workspaces):
                await show(workspaces)
            case .failure(.cancelled):
                break
            case .failure:
                errorMessage = ArtiseWorkspacesL10n.text("screen_artise_id_error")
            }
        }
    }
    
    func open(_ workspace: ArtiseIDWorkspace) {
        guard !isWorking else { return }
        errorMessage = nil
        Task {
            isWorking = true
            defer { isWorking = false }
            await openWorkspace(workspace)
        }
    }
    
    /// "Do you have your workspace's name? Type it": today's screen.
    func typeWorkspace() {
        actions.send(.login)
    }
    
    /// Scanning the QR code another phone shows (Settings → Link new device there).
    var canScanQRCode: Bool {
        !ProcessInfo.processInfo.isiOSAppOnMac
    }
    
    func scanQRCode() {
        actions.send(.loginWithQR)
    }
    
    /// Back to the sign-in buttons, forgetting this Artise ID account's tokens.
    func showProviders() {
        ArtiseIDSession.shared.forget()
        errorMessage = nil
        phase = .providers
    }
    
    // MARK: - Private
    
    /// One workspace opens straight away; several are listed; none explains how to get in.
    private func show(_ workspaces: [ArtiseIDWorkspace]) async {
        switch workspaces.count {
        case 0:
            phase = .noWorkspaces
        case 1:
            phase = .workspaces(workspaces)
            await openWorkspace(workspaces[0])
        default:
            phase = .workspaces(workspaces)
        }
    }
    
    /// The workspace's sign-in, as from "Your workspace": with Artise ID's session open, its page shows nothing.
    private func openWorkspace(_ workspace: ArtiseIDWorkspace) async {
        userIndicatorController.submitIndicator(UserIndicator(type: .modal, title: L10n.commonLoading, persistent: true))
        defer { userIndicatorController.retractAllIndicators() }
        let file = await ArtiseWorkspaces.shared.client.file(serverName: workspace.serverName)
        let address = workspace.slug.map(WorkspaceAddress.slug) ?? .serverName(workspace.serverName)
        switch await signInStarter.start(workspace.resolved(file: file), address: address, window: window) {
        case .password:
            actions.send(.loginDirectlyWithPassword(loginHint: nil))
        case .oAuth(let data, let window):
            actions.send(.loginDirectlyWithOAuth(data: data, window: window))
        case .failed(let message):
            errorMessage = message
        }
    }
}

struct ArtiseStartScreen: View {
    @Bindable var model: ArtiseStartScreenModel
    let fallback: AnyView
    
    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { AuthenticationStartScreenBackgroundImage() }
            case .fallback:
                fallback
            case .providers, .workspaces, .noWorkspaces:
                content
            }
        }
        .introspect(.window, on: .supportedVersions) { window in
            model.window = window
        }
    }
    
    private var content: some View {
        FullscreenDialog(topPadding: 48) {
            VStack(spacing: 24) {
                AuthenticationStartLogo(size: 120, hideBrandChrome: false, isOnGradient: true)
                Text(ArtiseWorkspacesL10n.text("screen_artise_id_title"))
                    .font(.compound.headingLGBold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if model.phase == .providers {
                    Text(ArtiseWorkspacesL10n.text("screen_artise_id_subtitle"))
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                        .multilineTextAlignment(.center)
                }
                phaseContent
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textCriticalPrimary)
                        .multilineTextAlignment(.center)
                }
            }
            .readableFrame()
        } bottomContent: {
            VStack(spacing: 12) {
                if model.canScanQRCode {
                    Button(ArtiseWorkspacesL10n.text("screen_artise_id_qr_code"), action: model.scanQRCode)
                        .buttonStyle(.compound(.textLink, size: .medium))
                }
                Button(ArtiseWorkspacesL10n.text("screen_artise_id_type_workspace"), action: model.typeWorkspace)
                    .buttonStyle(.compound(.textLink, size: .medium))
            }
            .disabled(model.isWorking)
        }
        .background { AuthenticationStartScreenBackgroundImage() }
        .navigationBarHidden(true)
    }
    
    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .workspaces(let workspaces):
            workspaceList(workspaces)
        case .noWorkspaces:
            VStack(spacing: 16) {
                Text(ArtiseWorkspacesL10n.text("screen_artise_id_no_workspaces"))
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
                Button(ArtiseWorkspacesL10n.text("screen_artise_id_other_account"), action: model.showProviders)
                    .buttonStyle(.compound(.secondary))
            }
        default:
            providerButtons
        }
    }
    
    /// Apple first (App Store guideline 4.8), then Google, Microsoft and email (Artise ID's own page).
    private var providerButtons: some View {
        VStack(spacing: 12) {
            Button { model.signIn(with: .apple) } label: {
                Label(ArtiseWorkspacesL10n.text("screen_artise_id_apple"), systemImage: "apple.logo")
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textOnSolidPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.compound.bgActionPrimaryRest, in: Capsule())
            }
            .buttonStyle(.plain)
            Button(ArtiseWorkspacesL10n.text("screen_artise_id_google")) { model.signIn(with: .google) }
                .buttonStyle(.compound(.secondary))
            Button(ArtiseWorkspacesL10n.text("screen_artise_id_microsoft")) { model.signIn(with: .microsoft) }
                .buttonStyle(.compound(.secondary))
            Button(ArtiseWorkspacesL10n.text("screen_artise_id_email")) { model.signIn(with: nil) }
                .buttonStyle(.compound(.secondary))
        }
        .disabled(model.isWorking)
    }
    
    private func workspaceList(_ workspaces: [ArtiseIDWorkspace]) -> some View {
        VStack(spacing: 12) {
            Text(ArtiseWorkspacesL10n.text("screen_artise_id_pick_workspace"))
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textSecondary)
                .multilineTextAlignment(.center)
            ForEach(workspaces) { workspace in
                Button { model.open(workspace) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                            .font(.compound.bodyLGSemibold)
                            .foregroundStyle(.compound.textPrimary)
                        Text(workspace.serverName)
                            .font(.compound.bodySM)
                            .foregroundStyle(.compound.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.compound.bgSubtleSecondary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
            Button(ArtiseWorkspacesL10n.text("screen_artise_id_other_account"), action: model.showProviders)
                .buttonStyle(.compound(.tertiary))
        }
        .disabled(model.isWorking)
    }
}
