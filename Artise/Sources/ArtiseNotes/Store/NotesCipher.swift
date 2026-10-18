//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

/// Encrypts what the notes store writes to disk. These are families' private notes.
public protocol NotesCipher: Sendable {
    func seal(_ plaintext: Data) throws -> Data
    func open(_ sealed: Data) throws -> Data
}

#if canImport(CryptoKit)
/// AES-256-GCM: every write gets a fresh nonce, and a tampered or truncated file fails to open.
public struct AESGCMNotesCipher: NotesCipher {
    private let key: SymmetricKey
    
    public init(keyData: Data) {
        key = SymmetricKey(data: keyData)
    }
    
    public func seal(_ plaintext: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw NotesStoreError.cannotEncrypt
        }
        return combined
    }
    
    public func open(_ sealed: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }
}
#endif

#if canImport(Security)
/// Keeps each account's notes key in the Keychain, on this device only, readable after the first unlock
/// (so a sync can finish in the background), and never in backups.
public struct KeychainNotesKeyStore: Sendable {
    private static let service = "co.artise.notes"
    
    public init() { }
    
    /// The account's key, created on first use.
    public func key(account: String) throws -> Data {
        if let existing = try read(account: account) {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NotesStoreError.cannotCreateKey
        }
        let key = Data(bytes)
        let attributes: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                           kSecAttrService: Self.service,
                                           kSecAttrAccount: account,
                                           kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                           kSecValueData: key]
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw NotesStoreError.cannotCreateKey
        }
        return key
    }
    
    /// Forgets the account's key, which makes its notes on the phone unreadable for good.
    public func deleteKey(account: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                      kSecAttrService: Self.service,
                                      kSecAttrAccount: account]
        SecItemDelete(query as CFDictionary)
    }
    
    private func read(account: String) throws -> Data? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                      kSecAttrService: Self.service,
                                      kSecAttrAccount: account,
                                      kSecReturnData: true,
                                      kSecMatchLimit: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw NotesStoreError.cannotReadKey(status)
        }
    }
}
#endif
