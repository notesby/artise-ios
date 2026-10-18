//
// Copyright 2026 Artise.
//
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
#if canImport(CommonCrypto) && canImport(CryptoKit)
import CommonCrypto
import CryptoKit
#endif

/// A file encrypted for an encrypted chat, and what the people in it need to decrypt it.
public struct EncryptedAttachment: Sendable {
    public let data: Data
    /// The key, in the JSON Web Key's unpadded base64url.
    public let key: String
    /// Unpadded base64.
    public let iv: String
    /// The encrypted bytes' SHA-256, unpadded base64.
    public let sha256: String
    
    public init(data: Data, key: String, iv: String, sha256: String) {
        self.data = data
        self.key = key
        self.iv = iv
        self.sha256 = sha256
    }
}

public enum AttachmentEncryptionError: Error {
    case cannotEncrypt
    case hashMismatch
    case badKey
}

#if canImport(CommonCrypto) && canImport(CryptoKit)
/// Matrix's attachment encryption (v2), as for photos sent in encrypted chats: AES-256-CTR with a new random key
/// for each file, and a counter starting at 0 in the IV's last 8 bytes. The same as the Android app.
public enum AttachmentEncryption {
    public static func encrypt(_ plain: Data) throws(AttachmentEncryptionError) -> EncryptedAttachment {
        var generator = SystemRandomNumberGenerator()
        let key = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let iv = Data((0..<8).map { _ in UInt8.random(in: .min ... .max, using: &generator) } + [UInt8](repeating: 0, count: 8))
        let encrypted = try aesCTR(plain, key: key, iv: iv)
        return EncryptedAttachment(data: encrypted,
                                   key: base64URL(key),
                                   iv: base64(iv),
                                   sha256: base64(Data(SHA256.hash(data: encrypted))))
    }
    
    /// The other way, for tests: checks the hash first, like the receiving app.
    public static func decrypt(_ attachment: EncryptedAttachment) throws(AttachmentEncryptionError) -> Data {
        guard base64(Data(SHA256.hash(data: attachment.data))) == attachment.sha256 else { throw .hashMismatch }
        guard let key = Data(base64Encoded: padded(attachment.key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"))),
              let iv = Data(base64Encoded: padded(attachment.iv)) else {
            throw .badKey
        }
        return try aesCTR(attachment.data, key: key, iv: iv)
    }
    
    /// CTR mode is its own inverse: the same call encrypts and decrypts.
    private static func aesCTR(_ input: Data, key: Data, iv: Data) throws(AttachmentEncryptionError) -> Data {
        var cryptor: CCCryptorRef?
        let created = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding),
                                        ivBytes.baseAddress, keyBytes.baseAddress, key.count, nil, 0, 0,
                                        CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
            }
        }
        guard created == kCCSuccess, let cryptor else { throw .cannotEncrypt }
        defer { CCCryptorRelease(cryptor) }
        var output = Data(count: input.count)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                CCCryptorUpdate(cryptor, inputBytes.baseAddress, input.count, outputBytes.baseAddress, input.count, &moved)
            }
        }
        guard status == kCCSuccess, moved == input.count else { throw .cannotEncrypt }
        return output
    }
    
    private static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
    
    private static func base64URL(_ data: Data) -> String {
        base64(data).replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }
    
    private static func padded(_ base64: String) -> String {
        base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)
    }
}
#endif
