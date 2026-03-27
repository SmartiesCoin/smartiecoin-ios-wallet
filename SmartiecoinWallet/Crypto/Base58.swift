import Foundation
import CryptoKit

enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let base = 58

    static func encode(_ data: Data) -> String {
        var bytes = [UInt8](data)
        var result = [Character]()

        while !bytes.isEmpty {
            var remainder = 0
            var quotient = [UInt8]()

            for byte in bytes {
                let value = remainder * 256 + Int(byte)
                let digit = value / base
                remainder = value % base

                if !quotient.isEmpty || digit > 0 {
                    quotient.append(UInt8(digit))
                }
            }

            result.insert(alphabet[remainder], at: 0)
            bytes = quotient
        }

        for byte in data {
            if byte == 0 {
                result.insert(alphabet[0], at: 0)
            } else {
                break
            }
        }

        return String(result)
    }

    static func decode(_ string: String) -> Data? {
        var result = [UInt8]()

        for char in string {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            var carry = index

            for i in stride(from: result.count - 1, through: 0, by: -1) {
                carry += Int(result[i]) * base
                result[i] = UInt8(carry & 0xFF)
                carry >>= 8
            }

            while carry > 0 {
                result.insert(UInt8(carry & 0xFF), at: 0)
                carry >>= 8
            }
        }

        for char in string {
            if char == alphabet[0] {
                result.insert(0, at: 0)
            } else {
                break
            }
        }

        return Data(result)
    }

    static func checkEncode(_ data: Data) -> String {
        let checksum = doubleSHA256(data).prefix(4)
        return encode(data + checksum)
    }

    static func checkDecode(_ string: String) -> Data? {
        guard let decoded = decode(string), decoded.count >= 4 else { return nil }
        let payload = decoded.dropLast(4)
        let checksum = decoded.suffix(4)
        let expected = doubleSHA256(Data(payload)).prefix(4)
        guard checksum == expected else { return nil }
        return Data(payload)
    }

    static func doubleSHA256(_ data: Data) -> Data {
        let first = SHA256.hash(data: data)
        let second = SHA256.hash(data: Data(first))
        return Data(second)
    }
}
