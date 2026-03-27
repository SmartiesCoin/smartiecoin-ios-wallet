import Foundation
import CryptoKit
import CommonCrypto

enum WalletEncryption {
    static func encrypt(plaintext: String, password: String) throws -> String {
        let salt = generateRandomBytes(count: 16)
        let key = try deriveKey(password: password, salt: salt)

        let sealedBox = try AES.GCM.seal(Data(plaintext.utf8), using: key)

        guard let combined = sealedBox.combined else {
            throw WalletError.encryptionFailed
        }

        // Format: salt(16) + combined(nonce(12) + ciphertext + tag(16))
        var result = Data()
        result.append(salt)
        result.append(combined)
        return result.hexString
    }

    static func decrypt(encryptedHex: String, password: String) throws -> String {
        guard let data = Data(hexString: encryptedHex), data.count > 16 else {
            throw WalletError.decryptionFailed
        }

        let salt = data.prefix(16)
        let sealedData = data.dropFirst(16)
        let key = try deriveKey(password: password, salt: Data(salt))

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            guard let text = String(data: decrypted, encoding: .utf8) else {
                throw WalletError.decryptionFailed
            }
            return text
        } catch is WalletError {
            throw WalletError.wrongPassword
        } catch {
            throw WalletError.wrongPassword
        }
    }

    // Use CommonCrypto's native PBKDF2 - much faster than pure Swift
    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derivedBytes = [UInt8](repeating: 0, count: 32)

        let status = passwordData.withUnsafeBytes { passwordPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                    passwordData.count,
                    saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    100_000,
                    &derivedBytes,
                    32
                )
            }
        }

        guard status == kCCSuccess else {
            throw WalletError.encryptionFailed
        }

        return SymmetricKey(data: derivedBytes)
    }

    private static func generateRandomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

enum WalletError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case wrongPassword
    case invalidMnemonic
    case keyDerivationFailed
    case invalidAddress
    case insufficientFunds
    case transactionFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "Encryption failed"
        case .decryptionFailed: return "Decryption failed"
        case .wrongPassword: return "Wrong password"
        case .invalidMnemonic: return "Invalid mnemonic phrase"
        case .keyDerivationFailed: return "Key derivation failed"
        case .invalidAddress: return "Invalid Smartiecoin address"
        case .insufficientFunds: return "Insufficient funds"
        case .transactionFailed(let msg): return "Transaction failed: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexString: String) {
        let hex = hexString.dropFirst(hexString.hasPrefix("0x") ? 2 : 0)
        guard hex.count % 2 == 0 else { return nil }

        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
