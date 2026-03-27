import Foundation
import CryptoKit
import secp256k1

enum BIP32 {

    enum BIP32Error: Error {
        case invalidSeed
        case invalidPath
        case invalidKey
        case keyDerivationFailed
    }

    // secp256k1 curve order n
    private static let curveOrderN: [UInt8] = [
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE,
        0xBA, 0xAE, 0xDC, 0xE6, 0xAF, 0x48, 0xA0, 0x3B,
        0xBF, 0xD2, 0x5E, 0x8C, 0xD0, 0x36, 0x41, 0x41
    ]

    // MARK: - Public Interface

    /// Derives a master key and chain code from a BIP39 seed using HMAC-SHA512.
    /// - Parameter seed: The BIP39 seed (typically 64 bytes).
    /// - Returns: A tuple of the 32-byte private key and 32-byte chain code.
    static func masterKeyFromSeed(_ seed: Data) throws -> (privateKey: Data, chainCode: Data) {
        guard !seed.isEmpty else {
            throw BIP32Error.invalidSeed
        }

        let hmacKey = SymmetricKey(data: "Bitcoin seed".data(using: .utf8)!)
        let hmac = HMAC<SHA512>.authenticationCode(for: seed, using: hmacKey)
        let hmacData = Data(hmac)

        let privateKey = hmacData.prefix(32)
        let chainCode = hmacData.suffix(32)

        // Verify the private key is valid (non-zero and less than curve order)
        guard isValidPrivateKey(privateKey) else {
            throw BIP32Error.invalidKey
        }

        return (privateKey: Data(privateKey), chainCode: Data(chainCode))
    }

    /// Derives a child key from a seed following a BIP32 derivation path.
    /// - Parameters:
    ///   - seed: The BIP39 seed.
    ///   - path: A derivation path string such as "m/44'/5001'/0'/0/0".
    /// - Returns: A tuple of the derived 32-byte private key and 32-byte chain code.
    static func deriveKeyFromPath(seed: Data, path: String) throws -> (privateKey: Data, chainCode: Data) {
        let components = path.split(separator: "/")

        guard let first = components.first, first == "m" else {
            throw BIP32Error.invalidPath
        }

        var result = try masterKeyFromSeed(seed)

        for component in components.dropFirst() {
            let hardened = component.hasSuffix("'")
            let indexString = hardened ? String(component.dropLast()) : String(component)

            guard let index = UInt32(indexString) else {
                throw BIP32Error.invalidPath
            }

            let childIndex: UInt32
            if hardened {
                childIndex = index | 0x80000000
            } else {
                childIndex = index
            }

            result = try deriveChild(
                parentKey: result.privateKey,
                parentChainCode: result.chainCode,
                index: childIndex
            )
        }

        return result
    }

    /// Computes the 33-byte compressed public key for a given private key.
    /// - Parameter privateKey: A 32-byte private key.
    /// - Returns: The 33-byte compressed SEC1 public key.
    static func publicKeyFromPrivateKey(_ privateKey: Data) throws -> Data {
        let privKey = try secp256k1.Signing.PrivateKey(rawRepresentation: privateKey)
        return Data(privKey.publicKey.rawRepresentation)
    }

    // MARK: - Private Helpers

    /// Derives a child key from a parent key and chain code at a given index.
    private static func deriveChild(
        parentKey: Data,
        parentChainCode: Data,
        index: UInt32
    ) throws -> (privateKey: Data, chainCode: Data) {
        var data = Data()

        if index >= 0x80000000 {
            // Hardened child: 0x00 || parentKey || index (big-endian)
            data.append(0x00)
            data.append(parentKey)
        } else {
            // Normal child: compressed public key || index (big-endian)
            let pubKey = try publicKeyFromPrivateKey(parentKey)
            data.append(pubKey)
        }

        // Append index as 4 bytes big-endian
        var indexBE = index.bigEndian
        data.append(Data(bytes: &indexBE, count: 4))

        let hmacKey = SymmetricKey(data: parentChainCode)
        let hmac = HMAC<SHA512>.authenticationCode(for: data, using: hmacKey)
        let hmacData = Data(hmac)

        let il = Data(hmacData.prefix(32))
        let childChainCode = Data(hmacData.suffix(32))

        // childKey = (parse256(IL) + parentKey) mod n
        let childKey = try addModN(il, parentKey)

        guard isValidPrivateKey(childKey) else {
            throw BIP32Error.keyDerivationFailed
        }

        return (privateKey: childKey, chainCode: childChainCode)
    }

    /// Adds two 256-bit integers (as 32-byte big-endian Data) modulo the secp256k1 curve order n.
    private static func addModN(_ a: Data, _ b: Data) throws -> Data {
        guard a.count == 32, b.count == 32 else {
            throw BIP32Error.invalidKey
        }

        let aBytes = [UInt8](a)
        let bBytes = [UInt8](b)

        // Add with carry (big-endian, process from least significant byte)
        var result = [UInt8](repeating: 0, count: 32)
        var carry: UInt16 = 0

        for i in stride(from: 31, through: 0, by: -1) {
            let sum = UInt16(aBytes[i]) + UInt16(bBytes[i]) + carry
            result[i] = UInt8(sum & 0xFF)
            carry = sum >> 8
        }

        // If result >= n, subtract n
        if carry > 0 || compareBytes(result, curveOrderN) >= 0 {
            var borrow: Int16 = 0
            for i in stride(from: 31, through: 0, by: -1) {
                let diff = Int16(result[i]) - Int16(curveOrderN[i]) - borrow
                if diff < 0 {
                    result[i] = UInt8((diff + 256) & 0xFF)
                    borrow = 1
                } else {
                    result[i] = UInt8(diff & 0xFF)
                    borrow = 0
                }
            }
        }

        return Data(result)
    }

    /// Compares two 32-byte big-endian byte arrays.
    /// Returns negative if a < b, zero if a == b, positive if a > b.
    private static func compareBytes(_ a: [UInt8], _ b: [UInt8]) -> Int {
        for i in 0..<32 {
            if a[i] < b[i] { return -1 }
            if a[i] > b[i] { return 1 }
        }
        return 0
    }

    /// Checks that a private key is non-zero and less than the curve order n.
    private static func isValidPrivateKey(_ key: Data) -> Bool {
        guard key.count == 32 else { return false }

        let bytes = [UInt8](key)

        // Must not be zero
        let isZero = bytes.allSatisfy { $0 == 0 }
        if isZero { return false }

        // Must be less than curve order n
        if compareBytes(bytes, curveOrderN) >= 0 {
            return false
        }

        return true
    }
}
