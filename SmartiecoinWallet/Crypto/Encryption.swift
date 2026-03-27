import Foundation
import CryptoKit

enum WalletEncryption {
    static func encrypt(plaintext: String, password: String) throws -> String {
        let salt = generateRandomBytes(count: 16)
        let nonce = generateRandomBytes(count: 12)
        let key = deriveKey(password: password, salt: salt)

        let sealedBox = try AES.GCM.seal(
            Data(plaintext.utf8),
            using: key,
            nonce: try AES.GCM.Nonce(data: nonce)
        )

        guard let ciphertext = sealedBox.combined else {
            throw WalletError.encryptionFailed
        }

        // Format: salt(16) + nonce(12) + ciphertext+tag
        // AES.GCM.seal combined = nonce(12) + ciphertext + tag(16)
        // We store: salt(16) + combined
        var result = Data()
        result.append(salt)
        result.append(ciphertext)
        return result.hexString
    }

    static func decrypt(encryptedHex: String, password: String) throws -> String {
        guard let combined = Data(hexString: encryptedHex) else {
            throw WalletError.decryptionFailed
        }

        guard combined.count > 16 else {
            throw WalletError.decryptionFailed
        }

        let salt = combined.prefix(16)
        let sealedData = combined.dropFirst(16)
        let key = deriveKey(password: password, salt: salt)

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            guard let text = String(data: decrypted, encoding: .utf8) else {
                throw WalletError.decryptionFailed
            }
            return text
        } catch {
            throw WalletError.wrongPassword
        }
    }

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: pbkdf2(password: passwordData, salt: salt)),
            outputByteCount: 32
        )
        return derivedKey
    }

    private static func pbkdf2(password: Data, salt: Data, iterations: Int = 100_000, keyLength: Int = 32) -> Data {
        var result = Data(count: keyLength)
        var block = 1
        var derived = Data()

        while derived.count < keyLength {
            var u = hmacSHA256(key: password, data: salt + withUnsafeBytes(of: UInt32(block).bigEndian) { Data($0) })
            var f = u

            for _ in 1..<iterations {
                u = hmacSHA256(key: password, data: u)
                for j in 0..<f.count {
                    f[j] ^= u[j]
                }
            }

            derived.append(f)
            block += 1
        }

        return derived.prefix(keyLength)
    }

    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(hmac)
    }

    private static func generateRandomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            fatalError("Failed to generate random bytes")
        }
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
