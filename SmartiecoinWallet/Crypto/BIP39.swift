import Foundation
import CryptoKit
import CommonCrypto

enum BIP39 {
    static func generateMnemonic() -> String {
        var entropy = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, 16, &entropy)
        if status != errSecSuccess {
            entropy = (0..<16).map { _ in UInt8.random(in: 0...255) }
        }
        return entropyToMnemonic(Data(entropy))
    }

    static func mnemonicToSeed(mnemonic: String, passphrase: String = "") -> Data {
        let salt = "mnemonic\(passphrase)"
        var derivedBytes = [UInt8](repeating: 0, count: 64)

        let status = mnemonic.withCString { passwordPtr in
            Array(salt.utf8).withUnsafeBufferPointer { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPtr,
                    mnemonic.utf8.count,
                    saltPtr.baseAddress,
                    salt.utf8.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    2048,
                    &derivedBytes,
                    64
                )
            }
        }

        if status == kCCSuccess {
            return Data(derivedBytes)
        }

        // Fallback to pure Swift if CommonCrypto fails
        return pbkdf2SHA512Fallback(
            password: Data(mnemonic.utf8),
            salt: Data(salt.utf8),
            iterations: 2048,
            keyLength: 64
        )
    }

    static func validateMnemonic(_ mnemonic: String) -> Bool {
        let words = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .map(String.init)

        guard words.count == 12 else { return false }

        let wordlist = BIP39Wordlist.english
        var indices = [Int]()
        for word in words {
            guard let index = wordlist.firstIndex(of: word) else { return false }
            indices.append(index)
        }

        // 12 words = 132 bits = 128 bits entropy + 4 bits checksum
        var bits = [Bool]()
        for index in indices {
            for bit in (0..<11).reversed() {
                bits.append((index >> bit) & 1 == 1)
            }
        }

        var entropyBytes = [UInt8]()
        for i in stride(from: 0, to: 128, by: 8) {
            var byte: UInt8 = 0
            for j in 0..<8 {
                if bits[i + j] { byte |= (1 << (7 - j)) }
            }
            entropyBytes.append(byte)
        }

        let checksumBits = Array(bits[128..<132])
        let hash = Data(SHA256.hash(data: Data(entropyBytes)))
        let expectedBits = (0..<4).map { (hash[0] >> (7 - $0)) & 1 == 1 }

        return checksumBits == expectedBits
    }

    private static func entropyToMnemonic(_ entropy: Data) -> String {
        let hash = Data(SHA256.hash(data: entropy))
        let checksumBits = 4

        var bits = [Bool]()
        for byte in entropy {
            for bit in (0..<8).reversed() {
                bits.append((byte >> bit) & 1 == 1)
            }
        }
        for bit in 0..<checksumBits {
            bits.append((hash[0] >> (7 - bit)) & 1 == 1)
        }

        let wordlist = BIP39Wordlist.english
        var words = [String]()
        for i in stride(from: 0, to: bits.count, by: 11) {
            var index = 0
            for j in 0..<11 {
                if bits[i + j] { index |= (1 << (10 - j)) }
            }
            words.append(wordlist[index])
        }

        return words.joined(separator: " ")
    }

    // Fallback only - CommonCrypto is preferred
    private static func pbkdf2SHA512Fallback(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        var derived = Data()
        var block = 1

        while derived.count < keyLength {
            var blockSalt = salt
            var blockBE = UInt32(block).bigEndian
            blockSalt.append(Data(bytes: &blockBE, count: 4))

            var u = hmacSHA512(key: password, data: blockSalt)
            var f = u

            for _ in 1..<iterations {
                u = hmacSHA512(key: password, data: u)
                for j in 0..<f.count {
                    f[j] ^= u[j]
                }
            }

            derived.append(f)
            block += 1
        }

        return derived.prefix(keyLength)
    }

    private static func hmacSHA512(key: Data, data: Data) -> Data {
        let hmac = HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(hmac)
    }
}
