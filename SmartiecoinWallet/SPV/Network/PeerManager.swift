import Foundation
import Network

final class PeerManager: @unchecked Sendable {
    private var peers: [PeerConnection] = []
    private var knownAddresses: Set<String> = []
    private let lock = NSLock()

    var onPeerConnected: ((PeerConnection) -> Void)?
    var onPeerDisconnected: ((PeerConnection) -> Void)?
    var onMessage: ((PeerConnection, P2PCommand, Data) -> Void)?

    var allPeers: [PeerConnection] {
        lock.lock()
        defer { lock.unlock() }
        return peers
    }

    var connectedPeers: [PeerConnection] {
        lock.lock()
        defer { lock.unlock() }
        return peers.filter { $0.isConnected && $0.isHandshakeComplete }
    }

    var peerCount: Int { connectedPeers.count }

    var bestPeerHeight: Int32 {
        connectedPeers.map(\.peerHeight).max() ?? 0
    }

    func start() {
        // Add hardcoded seed nodes directly
        for (host, port) in P2PConfig.seedNodes {
            addPeerAddress(host: host, port: port)
        }

        // Try DNS seeds
        for seed in P2PConfig.dnsSeeds {
            addPeerAddress(host: seed, port: P2PConfig.port)
        }

        // Connect after short delay
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.connectToMorePeers()
        }
    }

    func stop() {
        lock.lock()
        let allPeers = peers
        peers.removeAll()
        knownAddresses.removeAll()
        lock.unlock()

        for peer in allPeers {
            peer.disconnect()
        }
    }

    func addPeerAddress(host: String, port: UInt16) {
        let key = "\(host):\(port)"
        lock.lock()
        let isNew = knownAddresses.insert(key).inserted
        lock.unlock()

        if isNew {
            connectToMorePeers()
        }
    }

    private func connectToMorePeers() {
        lock.lock()
        let activeCount = peers.filter { $0.isConnected }.count
        let needed = P2PConfig.targetPeers - activeCount
        guard needed > 0 else { lock.unlock(); return }

        let connectedKeys = Set(peers.filter { $0.isConnected }.map { "\($0.host):\($0.port)" })
        let allKeys = Set(peers.map { "\($0.host):\($0.port)" })
        let unconnected = knownAddresses.subtracting(allKeys)
        lock.unlock()

        for addr in unconnected.prefix(needed) {
            let parts = addr.split(separator: ":")
            guard parts.count == 2, let port = UInt16(parts[1]) else { continue }
            connectToPeer(host: String(parts[0]), port: port)
        }
    }

    private func connectToPeer(host: String, port: UInt16) {
        let peer = PeerConnection(host: host, port: port)

        peer.onHandshakeComplete = { [weak self, weak peer] in
            guard let self, let peer else { return }
            DispatchQueue.main.async {
                self.onPeerConnected?(peer)
            }
            peer.requestPeerAddresses()
        }

        peer.onDisconnected = { [weak self, weak peer] _ in
            guard let self, let peer else { return }
            DispatchQueue.main.async {
                self.onPeerDisconnected?(peer)
            }
            self.lock.lock()
            self.peers.removeAll { $0.id == peer.id }
            self.lock.unlock()

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.connectToMorePeers()
            }
        }

        peer.onMessage = { [weak self] command, payload in
            guard let self else { return }

            if command == .addr, let addrMsg = AddrMessage(from: payload) {
                for addr in addrMsg.addresses where addr.services & P2PConfig.requiredServices != 0 {
                    self.addPeerAddress(host: addr.ip, port: addr.port)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onMessage?(peer, command, payload)
            }
        }

        lock.lock()
        peers.append(peer)
        lock.unlock()

        peer.connect()
    }

    func broadcast(command: P2PCommand, payload: Data) {
        for peer in connectedPeers { peer.send(command: command, payload: payload) }
    }

    func requestHeaders(locatorHashes: [Data]) {
        guard let peer = connectedPeers.randomElement() else { return }
        peer.requestHeaders(locatorHashes: locatorHashes)
    }

    func sendBloomFilter(_ filter: BloomFilter) {
        for peer in connectedPeers { peer.sendFilterLoad(filter) }
    }

    func broadcastTransaction(data: Data) {
        for peer in connectedPeers { peer.broadcastTransaction(data: data) }
    }
}
