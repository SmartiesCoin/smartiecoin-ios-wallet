import Foundation

// MARK: - Version Message

struct VersionMessage {
    let protocolVersion: Int32
    let services: UInt64
    let timestamp: Int64
    let receiverAddress: NetworkAddress
    let senderAddress: NetworkAddress
    let nonce: UInt64
    let userAgent: String
    let startHeight: Int32
    let relay: Bool

    struct NetworkAddress {
        let services: UInt64
        let ip: String
        let port: UInt16
    }

    static func create(peerIP: String, peerPort: UInt16, blockHeight: Int32) -> VersionMessage {
        VersionMessage(
            protocolVersion: P2PConfig.protocolVersion,
            services: P2PConfig.services,
            timestamp: Int64(Date().timeIntervalSince1970),
            receiverAddress: NetworkAddress(services: P2PConfig.requiredServices, ip: peerIP, port: peerPort),
            senderAddress: NetworkAddress(services: P2PConfig.services, ip: "0.0.0.0", port: 0),
            nonce: UInt64.random(in: 0...UInt64.max),
            userAgent: P2PConfig.userAgent,
            startHeight: blockHeight,
            relay: true  // We want bloom-filtered relaying
        )
    }

    var serialized: Data {
        var data = Data()
        data.appendInt32LE(protocolVersion)
        data.appendUInt64LE(services)
        data.appendInt64LE(timestamp)
        data.appendNetworkAddress(services: receiverAddress.services, ip: receiverAddress.ip, port: receiverAddress.port)
        data.appendNetworkAddress(services: senderAddress.services, ip: senderAddress.ip, port: senderAddress.port)
        data.appendUInt64LE(nonce)
        data.appendVarString(userAgent)
        data.appendInt32LE(startHeight)
        data.append(relay ? 1 : 0)
        return data
    }

    init?(from data: Data) {
        guard data.count >= 85 else { return nil }
        protocolVersion = data.readInt32LE(at: 0)
        services = data.readUInt64LE(at: 4)
        timestamp = data.readInt64LE(at: 12)
        receiverAddress = NetworkAddress(services: data.readUInt64LE(at: 20), ip: "0.0.0.0", port: 0)
        senderAddress = NetworkAddress(services: data.readUInt64LE(at: 46), ip: "0.0.0.0", port: 0)
        nonce = data.readUInt64LE(at: 72)

        var offset = 80
        guard let uaLen = data.readVarInt(at: &offset) else { return nil }
        guard offset + uaLen + 4 <= data.count else { return nil }
        userAgent = String(data: data.subdata(in: offset..<(offset + uaLen)), encoding: .utf8) ?? ""
        offset += uaLen
        startHeight = data.readInt32LE(at: offset)
        offset += 4
        relay = offset < data.count ? data.readUInt8(at: offset) != 0 : true
    }

    init(protocolVersion: Int32, services: UInt64, timestamp: Int64,
         receiverAddress: NetworkAddress, senderAddress: NetworkAddress,
         nonce: UInt64, userAgent: String, startHeight: Int32, relay: Bool) {
        self.protocolVersion = protocolVersion
        self.services = services
        self.timestamp = timestamp
        self.receiverAddress = receiverAddress
        self.senderAddress = senderAddress
        self.nonce = nonce
        self.userAgent = userAgent
        self.startHeight = startHeight
        self.relay = relay
    }
}

// MARK: - GetHeaders Message

struct GetHeadersMessage {
    let version: UInt32
    let locatorHashes: [Data]  // Block locator hashes (32 bytes each)
    let hashStop: Data         // 32 bytes, all zeros to get max headers

    var serialized: Data {
        var data = Data()
        data.appendUInt32LE(version)
        data.appendVarInt(locatorHashes.count)
        for hash in locatorHashes {
            data.append(hash)
        }
        data.append(hashStop)
        return data
    }

    static func create(locatorHashes: [Data]) -> GetHeadersMessage {
        GetHeadersMessage(
            version: UInt32(P2PConfig.protocolVersion),
            locatorHashes: locatorHashes,
            hashStop: Data(repeating: 0, count: 32)
        )
    }
}

// MARK: - Headers Message (response)

struct HeadersMessage {
    let headers: [BlockHeader]

    init?(from data: Data) {
        var offset = 0
        guard let count = data.readVarInt(at: &offset) else { return nil }
        guard count <= P2PConfig.maxHeaders else { return nil }

        var hdrs = [BlockHeader]()
        for _ in 0..<count {
            guard offset + 80 <= data.count else { return nil }
            let headerData = data.subdata(in: offset..<(offset + 80))
            guard let header = BlockHeader(from: headerData) else { return nil }
            hdrs.append(header)
            offset += 80

            // Skip transaction count (varint, should be 0 in headers message)
            guard let _ = data.readVarInt(at: &offset) else { return nil }
        }

        self.headers = hdrs
    }
}

// MARK: - Ping / Pong

struct PingMessage {
    let nonce: UInt64

    var serialized: Data {
        var data = Data()
        data.appendUInt64LE(nonce)
        return data
    }

    init(nonce: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.nonce = nonce
    }

    init?(from data: Data) {
        guard data.count >= 8 else { return nil }
        self.nonce = data.readUInt64LE(at: 0)
    }
}

// MARK: - Inv / GetData Message

struct InvMessage {
    let inventory: [InvVector]

    init(inventory: [InvVector]) {
        self.inventory = inventory
    }

    init?(from data: Data) {
        var offset = 0
        guard let count = data.readVarInt(at: &offset) else { return nil }

        var inv = [InvVector]()
        for _ in 0..<count {
            guard let vector = InvVector(from: data, offset: &offset) else { return nil }
            inv.append(vector)
        }
        self.inventory = inv
    }

    var serialized: Data {
        var data = Data()
        data.appendVarInt(inventory.count)
        for item in inventory {
            data.append(item.serialized)
        }
        return data
    }
}

// MARK: - MerkleBlock Message

struct MerkleBlockMessage {
    let header: BlockHeader
    let totalTransactions: UInt32
    let hashes: [Data]       // 32-byte hashes
    let flags: Data

    init?(from data: Data) {
        guard data.count >= 84 else { return nil }

        let headerData = data.prefix(80)
        guard let hdr = BlockHeader(from: headerData) else { return nil }
        self.header = hdr

        self.totalTransactions = data.readUInt32LE(at: 80)

        var offset = 84
        guard let hashCount = data.readVarInt(at: &offset) else { return nil }

        var hashes = [Data]()
        for _ in 0..<hashCount {
            guard offset + 32 <= data.count else { return nil }
            hashes.append(data.subdata(in: offset..<(offset + 32)))
            offset += 32
        }
        self.hashes = hashes

        guard let flagCount = data.readVarInt(at: &offset) else { return nil }
        guard offset + flagCount <= data.count else { return nil }
        self.flags = data.subdata(in: offset..<(offset + flagCount))
    }
}

// MARK: - FilterLoad Message (BIP37)

struct FilterLoadMessage {
    let filter: Data
    let nHashFuncs: UInt32
    let nTweak: UInt32
    let nFlags: UInt8  // BLOOM_UPDATE_ALL = 1

    var serialized: Data {
        var data = Data()
        data.appendVarInt(filter.count)
        data.append(filter)
        data.appendUInt32LE(nHashFuncs)
        data.appendUInt32LE(nTweak)
        data.append(nFlags)
        return data
    }
}

// MARK: - Addr Message

struct AddrMessage {
    struct PeerAddr {
        let timestamp: UInt32
        let services: UInt64
        let ip: String
        let port: UInt16
    }

    let addresses: [PeerAddr]

    init?(from data: Data) {
        var offset = 0
        guard let count = data.readVarInt(at: &offset) else { return nil }

        var addrs = [PeerAddr]()
        for _ in 0..<count {
            guard offset + 30 <= data.count else { break }
            let timestamp = data.readUInt32LE(at: offset)
            let services = data.readUInt64LE(at: offset + 4)

            // Parse IPv4-mapped IPv6 address
            let ipStart = offset + 12 + 12  // skip services(8) + IPv6 prefix(12)
            let ip: String
            if ipStart + 4 <= data.count {
                ip = "\(data[ipStart]).\(data[ipStart+1]).\(data[ipStart+2]).\(data[ipStart+3])"
            } else {
                ip = "0.0.0.0"
            }

            let portOffset = offset + 12 + 16
            let port: UInt16 = portOffset + 2 <= data.count
                ? (UInt16(data[portOffset]) << 8) | UInt16(data[portOffset + 1])
                : 0

            addrs.append(PeerAddr(timestamp: timestamp, services: services, ip: ip, port: port))
            offset += 30
        }

        self.addresses = addrs
    }
}
