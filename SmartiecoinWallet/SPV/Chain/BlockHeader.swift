import Foundation
import CryptoKit

struct BlockHeader: Codable, Identifiable {
    let version: Int32
    let prevHash: Data      // 32 bytes
    let merkleRoot: Data    // 32 bytes
    let timestamp: UInt32
    let bits: UInt32        // Compact target
    let nonce: UInt32

    var id: Data { blockHash }

    // Block hash = double SHA256 of the 80-byte header (reversed for display)
    var blockHash: Data {
        Base58.doubleSHA256(serialized)
    }

    var blockHashHex: String {
        Data(blockHash.reversed()).hexString
    }

    var prevHashHex: String {
        Data(prevHash.reversed()).hexString
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    // 80-byte serialized header
    var serialized: Data {
        var data = Data(capacity: 80)
        data.appendInt32LE(version)
        data.append(prevHash)
        data.append(merkleRoot)
        data.appendUInt32LE(timestamp)
        data.appendUInt32LE(bits)
        data.appendUInt32LE(nonce)
        return data
    }

    init?(from data: Data) {
        guard data.count >= 80 else { return nil }
        self.version = data.readInt32LE(at: 0)
        self.prevHash = Data(data.subdata(in: 4..<36))
        self.merkleRoot = Data(data.subdata(in: 36..<68))
        self.timestamp = data.readUInt32LE(at: 68)
        self.bits = data.readUInt32LE(at: 72)
        self.nonce = data.readUInt32LE(at: 76)
    }

    init(version: Int32, prevHash: Data, merkleRoot: Data,
         timestamp: UInt32, bits: UInt32, nonce: UInt32) {
        self.version = version
        self.prevHash = prevHash
        self.merkleRoot = merkleRoot
        self.timestamp = timestamp
        self.bits = bits
        self.nonce = nonce
    }

    // Verify this header links to the expected previous hash
    func linksTo(previousHash: Data) -> Bool {
        prevHash == previousHash
    }
}

// MARK: - Genesis Block

extension BlockHeader {
    // Smartiecoin mainnet genesis block (from src/chainparams.cpp)
    // Hash: 00003aa43e9605a58b926822c0e9dfdc0e43d2b6691ec58fc763f72a25e03655
    // Merkle: 233980ab7b1153d283b0d20e9a7901fe4a5e1d9355f6b67b5d42d60a9d8a8caf
    // Time: 1771811462, Bits: 0x1e3fffff, Nonce: 275448
    static let genesis: BlockHeader = {
        // Merkle root in internal byte order (reversed from display hex)
        let merkle = Data([
            0xaf, 0x8c, 0x8a, 0x9d, 0x0a, 0xd6, 0x42, 0x5d,
            0x7b, 0xb6, 0xf6, 0x55, 0x93, 0x1d, 0x5e, 0x4a,
            0xfe, 0x01, 0x79, 0x9a, 0x0e, 0xd2, 0xb0, 0x83,
            0xd2, 0x53, 0x11, 0x7b, 0xab, 0x80, 0x39, 0x23
        ])
        return BlockHeader(
            version: 1,
            prevHash: Data(repeating: 0, count: 32),
            merkleRoot: merkle,
            timestamp: 1771811462,
            bits: 0x1e3fffff,
            nonce: 275448
        )
    }()

    // Expected genesis block hash for verification
    static let genesisHashHex = "00003aa43e9605a58b926822c0e9dfdc0e43d2b6691ec58fc763f72a25e03655"
}
