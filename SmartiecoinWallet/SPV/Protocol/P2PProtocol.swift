import Foundation
import CryptoKit

// MARK: - Network Constants

enum P2PConfig {
    // Smartiecoin mainnet magic bytes (from src/chainparams.cpp)
    // pchMessageStart = { 0xe4, 0xba, 0x93, 0xc7 }
    static let magic: UInt32 = 0xC793BAE4

    // Default P2P port (from src/chainparams.cpp nDefaultPort)
    static let port: UInt16 = 8383

    // Protocol version (from src/version.h PROTOCOL_VERSION)
    static let protocolVersion: Int32 = 70240

    // Services we advertise
    static let services: UInt64 = 0  // SPV node, no services

    // Services we want from peers
    static let requiredServices: UInt64 = 1  // NODE_NETWORK

    // User agent
    static let userAgent = "/SmartiecoinWallet:2.0.0/"

    // DNS seeds (from src/chainparams.cpp vSeeds)
    static let dnsSeeds: [String] = [
        "207.180.230.125",
        "smartiescoin.com"
    ]

    // Hardcoded seed nodes as fallback
    static let seedNodes: [(String, UInt16)] = [
        ("207.180.230.125", 8383),
    ]

    // Maximum headers per getheaders response
    static let maxHeaders = 2000

    // Target number of peer connections
    static let targetPeers = 4

    // Min peer protocol version (from src/version.h MIN_PEER_PROTO_VERSION)
    static let minPeerVersion: Int32 = 70221

    // Block time target: 60 seconds (1-minute blocks)
    static let targetBlockSpacing: Int = 60
}

// MARK: - P2P Command Types

enum P2PCommand: String {
    case version = "version"
    case verack = "verack"
    case ping = "ping"
    case pong = "pong"
    case getHeaders = "getheaders"
    case headers = "headers"
    case inv = "inv"
    case getdata = "getdata"
    case tx = "tx"
    case merkleblock = "merkleblock"
    case filterload = "filterload"
    case filteradd = "filteradd"
    case filterclear = "filterclear"
    case reject = "reject"
    case addr = "addr"
    case getaddr = "getaddr"
    case sendheaders = "sendheaders"
    case notfound = "notfound"

    var commandBytes: Data {
        var bytes = Data(rawValue.utf8)
        while bytes.count < 12 {
            bytes.append(0)
        }
        return bytes.prefix(12)
    }

    init?(fromBytes bytes: Data) {
        let trimmed = bytes.prefix(12)
        guard let str = String(data: trimmed, encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) else { return nil }
        self.init(rawValue: str)
    }
}

// MARK: - Inventory Types

enum InvType: UInt32 {
    case error = 0
    case tx = 1
    case block = 2
    case filteredBlock = 3
}

struct InvVector {
    let type: InvType
    let hash: Data  // 32 bytes

    var serialized: Data {
        var data = Data()
        data.appendUInt32LE(type.rawValue)
        data.append(hash)
        return data
    }

    init(type: InvType, hash: Data) {
        self.type = type
        self.hash = hash
    }

    init?(from data: Data, offset: inout Int) {
        guard offset + 36 <= data.count else { return nil }
        let typeRaw = data.readUInt32LE(at: offset)
        guard let t = InvType(rawValue: typeRaw) else { return nil }
        self.type = t
        self.hash = data.subdata(in: (offset + 4)..<(offset + 36))
        offset += 36
    }
}

// MARK: - Message Envelope

struct P2PMessageHeader {
    let magic: UInt32
    let command: P2PCommand
    let payloadLength: UInt32
    let checksum: Data  // 4 bytes

    static let size = 24  // 4 + 12 + 4 + 4

    init?(from data: Data) {
        guard data.count >= Self.size else { return nil }
        self.magic = data.readUInt32LE(at: 0)
        guard let cmd = P2PCommand(fromBytes: data.subdata(in: 4..<16)) else { return nil }
        self.command = cmd
        self.payloadLength = data.readUInt32LE(at: 16)
        self.checksum = data.subdata(in: 20..<24)
    }
}

enum P2PSerializer {
    static func buildMessage(command: P2PCommand, payload: Data) -> Data {
        var message = Data()

        // Magic
        message.appendUInt32LE(P2PConfig.magic)

        // Command (12 bytes, null-padded)
        message.append(command.commandBytes)

        // Payload length
        message.appendUInt32LE(UInt32(payload.count))

        // Checksum (first 4 bytes of double SHA256 of payload)
        let hash = Base58.doubleSHA256(payload)
        message.append(hash.prefix(4))

        // Payload
        message.append(payload)

        return message
    }

    static func verifyChecksum(payload: Data, expected: Data) -> Bool {
        let hash = Base58.doubleSHA256(payload)
        return hash.prefix(4) == expected
    }
}

// MARK: - Data Helpers for P2P

extension Data {
    func readUInt8(at offset: Int) -> UInt8 {
        self[startIndex + offset]
    }

    func readUInt16LE(at offset: Int) -> UInt16 {
        let start = startIndex + offset
        return UInt16(self[start]) | (UInt16(self[start + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        return UInt32(self[start])
            | (UInt32(self[start + 1]) << 8)
            | (UInt32(self[start + 2]) << 16)
            | (UInt32(self[start + 3]) << 24)
    }

    func readUInt64LE(at offset: Int) -> UInt64 {
        var val: UInt64 = 0
        for i in 0..<8 {
            val |= UInt64(self[startIndex + offset + i]) << (i * 8)
        }
        return val
    }

    func readInt32LE(at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32LE(at: offset))
    }

    func readInt64LE(at offset: Int) -> Int64 {
        Int64(bitPattern: readUInt64LE(at: offset))
    }

    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        for i in 0..<4 {
            append(UInt8((value >> (i * 8)) & 0xFF))
        }
    }

    mutating func appendUInt64LE(_ value: UInt64) {
        for i in 0..<8 {
            append(UInt8((value >> (i * 8)) & 0xFF))
        }
    }

    mutating func appendInt32LE(_ value: Int32) {
        appendUInt32LE(UInt32(bitPattern: value))
    }

    mutating func appendInt64LE(_ value: Int64) {
        appendUInt64LE(UInt64(bitPattern: value))
    }

    mutating func appendVarInt(_ value: Int) {
        if value < 0xFD {
            append(UInt8(value))
        } else if value <= 0xFFFF {
            append(0xFD)
            appendUInt16LE(UInt16(value))
        } else if value <= 0xFFFFFFFF {
            append(0xFE)
            appendUInt32LE(UInt32(value))
        } else {
            append(0xFF)
            appendUInt64LE(UInt64(value))
        }
    }

    mutating func appendVarString(_ str: String) {
        let bytes = Data(str.utf8)
        appendVarInt(bytes.count)
        append(bytes)
    }

    mutating func appendNetworkAddress(services: UInt64, ip: String, port: UInt16) {
        appendUInt64LE(services)
        // IPv4-mapped IPv6 address
        append(Data(repeating: 0, count: 10))
        append(contentsOf: [0xFF, 0xFF])
        // Parse IPv4
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        if parts.count == 4 {
            append(contentsOf: parts)
        } else {
            append(Data(repeating: 0, count: 4))
        }
        // Port (big-endian)
        append(UInt8((port >> 8) & 0xFF))
        append(UInt8(port & 0xFF))
    }

    func readVarInt(at offset: inout Int) -> Int? {
        guard offset < count else { return nil }
        let first = self[startIndex + offset]
        offset += 1

        if first < 0xFD {
            return Int(first)
        } else if first == 0xFD {
            guard offset + 2 <= count else { return nil }
            let val = readUInt16LE(at: offset)
            offset += 2
            return Int(val)
        } else if first == 0xFE {
            guard offset + 4 <= count else { return nil }
            let val = readUInt32LE(at: offset)
            offset += 4
            return Int(val)
        } else {
            guard offset + 8 <= count else { return nil }
            let val = readUInt64LE(at: offset)
            offset += 8
            return Int(val)
        }
    }
}
