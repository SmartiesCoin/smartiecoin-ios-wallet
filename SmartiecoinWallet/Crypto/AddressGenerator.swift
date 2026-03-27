import Foundation
import CryptoKit

enum AddressGenerator {
    static func p2pkhAddress(publicKey: Data) -> String {
        let sha256Hash = Data(SHA256.hash(data: publicKey))
        let ripemd160Hash = RIPEMD160.hash(data: sha256Hash)

        var addressData = Data([SmartiecoinNetwork.pubKeyHash])
        addressData.append(ripemd160Hash)

        return Base58.checkEncode(addressData)
    }

    static func pubKeyHashFromAddress(_ address: String) -> Data? {
        guard let decoded = Base58.checkDecode(address) else { return nil }
        guard decoded.count == 21 else { return nil }
        let version = decoded[0]
        guard version == SmartiecoinNetwork.pubKeyHash || version == SmartiecoinNetwork.scriptHash else { return nil }
        return decoded.dropFirst()
    }

    static func scriptPubKeyForP2PKH(pubKeyHash: Data) -> Data {
        var script = Data()
        script.append(0x76) // OP_DUP
        script.append(0xA9) // OP_HASH160
        script.append(0x14) // Push 20 bytes
        script.append(pubKeyHash)
        script.append(0x88) // OP_EQUALVERIFY
        script.append(0xAC) // OP_CHECKSIG
        return script
    }

    static func isValidAddress(_ address: String) -> Bool {
        guard address.count >= 26, address.count <= 35 else { return false }
        guard let first = address.first, first == "S" || first == "R" else { return false }
        return pubKeyHashFromAddress(address) != nil
    }
}
