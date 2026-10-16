//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import Combine
import Compound
import SwiftUI

/// "Your workspace": the first step of signing in, in place of choosing a server. It finds the workspace,
/// reads its look, sets up sign-in for its server, and continues exactly as the server picker would.
final class ArtiseWorkspaceScreenCoordinator: CoordinatorProtocol {
    private let parameters: ServerSelectionScreenCoordinatorParameters
    private let model: ArtiseWorkspaceScreenModel
    
    var actions: AnyPublisher<ServerSelectionScreenCoordinatorAction, Never> {
        model.actions.eraseToAnyPublisher()
    }
    
    init(parameters: ServerSelectionScreenCoordinatorParameters) {
        self.parameters = parameters
        model = ArtiseWorkspaceScreenModel(authenticationService: parameters.authenticationService,
                                           authenticationFlow: parameters.authenticationFlow,
                                           appSettings: parameters.appSettings,
                                           userIndicatorController: parameters.userIndicatorController)
    }
    
    func stop() {
        parameters.userIndicatorController.retractAllIndicators()
    }
    
    func toPresentable() -> AnyView {
        AnyView(ArtiseWorkspaceScreen(model: model))
    }
}

@MainActor @Observable
final class ArtiseWorkspaceScreenModel {
    var text: String
    private(set) var errorMessage: String?
    private(set) var isWorking = false
    @ObservationIgnored var window: UIWindow?
    
    @ObservationIgnored let actions = PassthroughSubject<ServerSelectionScreenCoordinatorAction, Never>()
    @ObservationIgnored private let authenticationService: AuthenticationServiceProtocol
    @ObservationIgnored private let authenticationFlow: AuthenticationFlow
    @ObservationIgnored private let appSettings: AppSettings
    @ObservationIgnored private let userIndicatorController: UserIndicatorControllerProtocol
    @ObservationIgnored private var inviteObserver: AnyCancellable?
    
    init(authenticationService: AuthenticationServiceProtocol,
         authenticationFlow: AuthenticationFlow,
         appSettings: AppSettings,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.authenticationService = authenticationService
        self.authenticationFlow = authenticationFlow
        self.appSettings = appSettings
        self.userIndicatorController = userIndicatorController
        text = ArtiseWorkspaces.shared.lastAddress ?? ""
        
        inviteObserver = ArtiseWorkspaces.shared.inviteAddresses.sink { [weak self] _ in
            self?.takeInvite()
        }
    }
    
    /// An invite link that just finished on its join page goes straight on to sign-in.
    func takeInvite() {
        guard let address = ArtiseWorkspaces.shared.takePendingInviteAddress() else { return }
        text = address
        submit()
    }
    
    func textChanged() {
        errorMessage = nil
    }
    
    func submit() {
        guard !isWorking else { return }
        guard let address = WorkspaceAddress(input: text) else {
            errorMessage = ArtiseWorkspacesL10n.text("screen_workspace_error_invalid")
            return
        }
        errorMessage = nil
        Task { await signIn(to: address) }
    }
    
    // MARK: - Private
    
    private func signIn(to address: WorkspaceAddress) async {
        isWorking = true
        startLoading()
        defer {
            stopLoading()
            isWorking = false
        }
        
        switch await ArtiseWorkspaces.shared.client.resolve(address) {
        case .ready(let workspace):
            guard await configure(for: workspace) else {
                MXLog.error("Sign-in isn't available for workspace server \(workspace.serverName)")
                errorMessage = String(format: ArtiseWorkspacesL10n.text("screen_workspace_error_sign_in_unavailable"),
                                      workspace.displayName ?? workspace.serverName)
                return
            }
            ArtiseWorkspaces.shared.didChoose(workspace, address: address)
            await continueToSignIn(workspace)
        case .notFound(let slug):
            errorMessage = String(format: ArtiseWorkspacesL10n.text("screen_workspace_error_not_found"), slug)
        case .paused:
            errorMessage = ArtiseWorkspacesL10n.text("screen_workspace_error_paused")
        case .rateLimited:
            errorMessage = ArtiseWorkspacesL10n.text("screen_workspace_error_rate_limited")
        case .unreachable:
            errorMessage = ArtiseWorkspacesL10n.text("screen_workspace_error_unreachable")
        }
    }
    
    /// The server's own discovery first; the workspace file's address if that fails.
    private func configure(for workspace: ResolvedWorkspace) async -> Bool {
        if case .success = await authenticationService.configure(for: workspace.serverName, flow: authenticationFlow) {
            return true
        }
        guard let homeserverURL = workspace.file?.homeserverURL else { return false }
        if case .success = await authenticationService.configure(for: homeserverURL.absoluteString, flow: authenticationFlow) {
            return true
        }
        return false
    }
    
    /// As the server picker does: a password form, or the server's own sign-in page. That page uses the workspace's
    /// own app client when it has one, which skips the "Continue to Artise" consent page.
    private func continueToSignIn(_ workspace: ResolvedWorkspace) async {
        guard authenticationService.homeserver.value.loginMode.supportsOAuthFlow else {
            actions.send(.continueWithPassword)
            return
        }
        let client = await ArtiseWorkspaces.shared.client.signInClient(for: workspace)
        appSettings.artiseUseOAuthClient(redirectURL: client.redirectURL,
                                         staticRegistrations: client.staticRegistrations.reduce(into: [:]) { registrations, entry in
                                             if let issuer = URL(string: entry.key) {
                                                 registrations[issuer] = entry.value
                                             }
                                         })
        guard let window else {
            MXLog.error("No window available for OAuth presentation")
            errorMessage = L10n.errorUnknown
            return
        }
        switch await authenticationService.urlForOAuthLogin(loginHint: nil) {
        case .success(let oAuthData):
            actions.send(.continueWithOAuth(data: oAuthData, window: window))
        case .failure(let error):
            MXLog.error("Failed to get OAuth login URL: \(error)")
            errorMessage = L10n.errorUnknown
        }
    }
    
    private func startLoading() {
        userIndicatorController.submitIndicator(UserIndicator(type: .modal, title: L10n.commonLoading, persistent: true))
    }
    
    private func stopLoading() {
        userIndicatorController.retractAllIndicators()
    }
}

struct ArtiseWorkspaceScreen: View {
    @Bindable var model: ArtiseWorkspaceScreenModel
    @FocusState private var isFieldFocused: Bool
    
    var body: some View {
        FullscreenDialog(topPadding: 24) {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 36)
                
                field
            }
            .readableFrame()
        } bottomContent: {
            ArtiseAccentButton(title: model.errorMessage == nil ? L10n.actionContinue : L10n.actionTryAgain,
                               accent: nil,
                               action: model.submit)
                .disabled(model.isWorking || model.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .background()
        .backgroundStyle(Color.compound.bgCanvasDefault)
        .navigationBarTitleDisplayMode(.inline)
        .introspect(.window, on: .supportedVersions) { window in
            model.window = window
        }
        .onAppear {
            isFieldFocused = true
            model.takeInvite()
        }
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            BigIcon(icon: \.host, style: .defaultSolid)
                .padding(.bottom, 8)
            
            Text(ArtiseWorkspacesL10n.text("screen_workspace_title"))
                .font(.compound.headingMDBold)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textPrimary)
            
            Text(ArtiseWorkspacesL10n.text("screen_workspace_subtitle"))
                .font(.compound.bodyMD)
                .multilineTextAlignment(.center)
                .foregroundColor(.compound.textSecondary)
        }
        .padding(.horizontal, 16)
    }
    
    private var field: some View {
        TextField(ArtiseWorkspacesL10n.text("screen_workspace_placeholder"), text: $model.text)
            .textFieldStyle(.compound(labelText: ArtiseWorkspacesL10n.text("screen_workspace_field_label"),
                                      footerText: model.errorMessage ?? ArtiseWorkspacesL10n.text("screen_workspace_field_footer"),
                                      state: model.errorMessage == nil ? .default : .error))
            .focused($isFieldFocused)
            .keyboardType(.URL)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .submitLabel(.go)
            .onChange(of: model.text) { model.textChanged() }
            .onSubmit(model.submit)
    }
}
