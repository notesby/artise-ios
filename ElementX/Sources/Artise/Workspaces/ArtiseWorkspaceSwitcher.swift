//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import ArtiseWorkspaces
import Compound
import SwiftUI

/// The workspaces signed in on this phone, the one on screen, and switching to or adding one.
///
/// Every workspace stays signed in, so all of them notify. `AppCoordinator` keeps the list and does the switching.
@MainActor @Observable
final class ArtiseWorkspaceSwitcher {
    static let shared = ArtiseWorkspaceSwitcher()
    
    struct OpenWorkspace: Identifiable, Equatable {
        let userID: String
        let name: String
        let logoURL: URL?
        
        var id: String {
            userID
        }
    }
    
    /// Sorted by name, so rows stay put when switching.
    private(set) var workspaces: [OpenWorkspace] = []
    private(set) var currentUserID: String?
    /// The Artise ID list or "Your workspace" is open to add a workspace, with the chats behind it.
    private(set) var isAdding = false
    
    @ObservationIgnored private var switchHandler: (String) -> Void = { _ in }
    @ObservationIgnored private var addHandler: () -> Void = { }
    @ObservationIgnored private var cancelAddingHandler: () -> Void = { }
    
    /// Called by `AppCoordinator` once, at launch.
    func setUp(switchTo: @escaping (String) -> Void, add: @escaping () -> Void, cancelAdding: @escaping () -> Void) {
        switchHandler = switchTo
        addHandler = add
        cancelAddingHandler = cancelAdding
    }
    
    /// Called by `AppCoordinator` whenever an account signs in or out, or another one is shown.
    func update(userIDs: [String], currentUserID: String?) {
        self.currentUserID = currentUserID
        workspaces = userIDs.map { userID in
            let workspace = ArtiseWorkspaces.shared.workspace(userID: userID)
            return OpenWorkspace(userID: userID,
                                 name: workspace?.displayName ?? WorkspaceHosts.serverName(userID: userID) ?? userID,
                                 logoURL: workspace?.branding?.logoURL)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    
    func setAdding(_ isAdding: Bool) {
        self.isAdding = isAdding
    }
    
    /// The signed-in account on the workspace at `serverName`, so the Artise ID list says "Already open".
    func openUserID(serverName: String) -> String? {
        workspaces.first { WorkspaceHosts.serverName(userID: $0.userID) == serverName.lowercased() }?.userID
    }
    
    /// Whether signing out of the account on screen leaves no workspace on this phone.
    var isLastWorkspace: Bool {
        workspaces.count <= 1
    }
    
    func switchTo(_ userID: String) {
        guard userID != currentUserID || isAdding else { return }
        switchHandler(userID)
    }
    
    func add() {
        addHandler()
    }
    
    func cancelAdding() {
        cancelAddingHandler()
    }
}

/// Opened from the workspace's name on the chat list and from Settings: every workspace on this phone, the one on
/// screen ticked, and "Add a workspace".
struct ArtiseWorkspaceSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    private let switcher = ArtiseWorkspaceSwitcher.shared
    
    var body: some View {
        ElementNavigationStack {
            Form {
                Section {
                    ForEach(switcher.workspaces) { workspace in
                        row(workspace)
                    }
                }
                Section {
                    ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_workspaces_add"), icon: \.plus),
                            kind: .button(action: add))
                }
            }
            .compoundList()
            .navigationTitle(ArtiseWorkspacesL10n.text("screen_artise_workspaces_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarButton(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func row(_ workspace: ArtiseWorkspaceSwitcher.OpenWorkspace) -> some View {
        let isCurrent = workspace.userID == switcher.currentUserID
        return ListRow(kind: .custom {
            Button { pick(workspace) } label: {
                HStack(spacing: 12) {
                    ArtiseWorkspaceLogo(url: workspace.logoURL, size: 32)
                    Text(workspace.name)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isCurrent {
                        CompoundIcon(\.check)
                            .foregroundStyle(.compound.iconAccentPrimary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, ListRowPadding.horizontal)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
        })
    }
    
    private func pick(_ workspace: ArtiseWorkspaceSwitcher.OpenWorkspace) {
        dismiss()
        switcher.switchTo(workspace.userID)
    }
    
    private func add() {
        dismiss()
        switcher.add()
    }
}

/// The workspace's logo and name at the top of the chat list; a tap opens the workspace switcher.
struct ArtiseWorkspaceTitleButton<Label: View>: View {
    let isEnabled: Bool
    @ViewBuilder let label: () -> Label
    
    @State private var isPresentingSwitcher = false
    
    var body: some View {
        if isEnabled {
            Button { isPresentingSwitcher = true } label: {
                HStack(spacing: 8) {
                    label()
                    CompoundIcon(\.chevronDown, size: .xSmall, relativeTo: .compound.headingLGBold)
                        .foregroundStyle(.compound.iconSecondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(ArtiseWorkspacesL10n.text("screen_artise_workspaces_title"))
            .sheet(isPresented: $isPresentingSwitcher) {
                ArtiseWorkspaceSwitcherSheet()
            }
        } else {
            label()
        }
    }
}

/// Settings: "Your workspaces", opening the same switcher as the chat list's title.
struct ArtiseWorkspacesSettingsRow: View {
    @State private var isPresentingSwitcher = false
    
    var body: some View {
        Section {
            ListRow(label: .default(title: ArtiseWorkspacesL10n.text("screen_artise_workspaces_title"), icon: \.home),
                    kind: .navigationLink { isPresentingSwitcher = true })
        }
        .sheet(isPresented: $isPresentingSwitcher) {
            ArtiseWorkspaceSwitcherSheet()
        }
    }
}
