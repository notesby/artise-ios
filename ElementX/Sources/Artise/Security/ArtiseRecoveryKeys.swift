//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import KeychainAccess
import LocalAuthentication
import SwiftUI

/// The account's recovery key, kept in iCloud Keychain (end-to-end encrypted by Apple; Artise's server never sees it),
/// so a new iPhone with the same Apple account unlocks the chats without asking (way 1 of the UX plan, approved 17 Oct).
/// It only reaches Apple devices: an Android phone gets the chats with the phone-to-phone QR or the key itself.
@MainActor @Observable
final class ArtiseRecoveryKeys {
    static let shared = ArtiseRecoveryKeys()
    
    @ObservationIgnored private var securityObserver: AnyCancellable?
    @ObservationIgnored private var userID: String?
    /// The one-time card on the chat list: only phone signed in, key saved here, not dismissed yet.
    private(set) var showsKeepKeyCard = false
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let cardDismissedKey = "artise.keepKeyCard.dismissed"
    
    // MARK: - Storage
    
    /// iCloud Keychain item for this account; it syncs only when the person has iCloud Keychain on.
    nonisolated static func save(_ key: String, userID: String) {
        do {
            try keychain.set(key, key: userID)
            MXLog.info("Saved the recovery key to iCloud Keychain")
        } catch {
            MXLog.error("Couldn't save the recovery key to iCloud Keychain: \(error)")
        }
    }
    
    nonisolated static func key(userID: String) -> String? {
        try? keychain.getString(userID)
    }
    
    nonisolated static func remove(userID: String) {
        try? keychain.remove(userID)
    }
    
    private nonisolated static var keychain: Keychain {
        Keychain(service: "co.artise.app.recovery-key").synchronizable(true).accessibility(.afterFirstUnlock)
    }
    
    // MARK: - The signed-in account
    
    /// Called when the session is ready. A new iPhone unlocks with the key from iCloud; a verified phone with no
    /// recovery yet sets it up, quietly, and keeps the key.
    func configure(with userSession: UserSessionProtocol?) {
        securityObserver = nil
        guard let userSession else {
            userID = nil
            return
        }
        let userID = userSession.clientProxy.userID
        self.userID = userID
        var isHandled = false
        securityObserver = userSession.sessionSecurityStatePublisher
            .filter { $0.verificationState != .unknown && $0.recoveryState != .unknown }
            .first()
            .sink { [weak self] state in
                guard !isHandled else { return }
                isHandled = true
                Task { await self?.handle(state, userSession: userSession, userID: userID) }
            }
    }
    
    private func handle(_ state: SessionSecurityState, userSession: UserSessionProtocol, userID: String) async {
        let backup = userSession.clientProxy.secureBackupController
        switch (state.verificationState, state.recoveryState) {
        case (.unverified, .enabled), (.unverified, .incomplete):
            guard let key = Self.key(userID: userID) else { return }
            MXLog.info("Unlocking the chats with the recovery key from iCloud Keychain")
            if case .failure = await backup.confirmRecoveryKey(key) {
                // The key was changed or reset on another phone: this copy can't help any more.
                MXLog.warning("The recovery key in iCloud Keychain no longer works; removing it")
                Self.remove(userID: userID)
            }
        case (.verified, .disabled):
            MXLog.info("Setting up recovery on first sign-in")
            // generateRecoveryKey saves the new key to iCloud Keychain (SecureBackupController, Artise hook).
            _ = await backup.generateRecoveryKey(withPassphrase: nil)
        default:
            break
        }
        await updateKeepKeyCard(userSession: userSession, userID: userID)
    }
    
    private func updateKeepKeyCard(userSession: UserSessionProtocol, userID: String) async {
        guard !defaults.bool(forKey: Self.cardDismissedKey), Self.key(userID: userID) != nil,
              case .success(true) = await userSession.clientProxy.isOnlyDeviceLeft() else {
            showsKeepKeyCard = false
            return
        }
        showsKeepKeyCard = true
    }
    
    func dismissKeepKeyCard() {
        defaults.set(true, forKey: Self.cardDismissedKey)
        showsKeepKeyCard = false
    }
    
    // MARK: - Showing the key
    
    /// The key, after Face ID, Touch ID or the passcode; `nil` when there's none here or it was cancelled.
    func revealKey() async -> String? {
        guard let userID, let key = Self.key(userID: userID) else { return nil }
        let context = LAContext()
        do {
            let reason = ArtiseWorkspacesL10n.text("screen_artise_recovery_key_reason")
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else { return nil }
        } catch {
            return nil
        }
        return key
    }
    
    var hasKey: Bool {
        userID.flatMap(Self.key(userID:)) != nil
    }
}
