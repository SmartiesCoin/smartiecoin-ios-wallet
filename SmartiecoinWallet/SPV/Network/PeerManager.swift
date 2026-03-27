import Foundation
import Network

/// Manages multiple peer connections for the SPV client
final class PeerManager: @unchecked Sendable {
    private var peers: [PeerConnection] = []
    private var knownAddresses: Set<String> = []
    private let queue = DispatchQueue(label: "com.smartiecoin.peermanager")

    // Callbacks
    var onPeerConnected: ((PeerConnection) -> Void)?
    var onPeerDisconnected: ((PeerConnection) -> Void)?
    var onMessage: ((PeerConnection, P2PCommand, Data) -> Void)?

    // State
    var connectedPeers: [PeerConnection] {
        peers.filter { $0.isConnected && $0.isHandshakeComplete }
    }

    var peerCount: Int {
        connectedPeers.count
    }

    var bestPeerHeight: Int32 {
        connectedPeers.map(\.peerHeight).max() ?? 0
    }

    // MARK: - Start / Stop

    func start() {
        discoverPeers()
    }

    func stop() {
        for peer in peers {
            peer.disconnect()
        }
        peers.removeAll()
    }

    // MARK: - Peer Discovery

    private func discoverPeers() {
        // Try DNS seeds first
        for seed in P2PConfig.dnsSeeds {
            resolveDNSSeed(seed)
        }

        // Use hardcoded seed nodes as fallback
        for (host, port) in P2PConfig.seedNodes {
            addPeerAddress(host: host, port: port)
        }

        // Connect to peers after short delay for DNS resolution
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.connectToMorePeers()
        }
    }

    private func resolveDNSSeed(_ hostname: String) {
        let host = NWEndpoint.Host(hostname)
        let params = NWParameters.tcp

        // Use a connection attempt to resolve DNS
        let endpoint = NWEndpoint.hostPort(host: host, port: NWEndpoint.Port(rawValue: P2PConfig.port)!)
        let connection = NWConnection(to: endpoint, using: params)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Got a connection - this IP works
                if case let .hostPort(resolvedHost, _) = connection.currentPath?.remoteEndpoint {
                    self?.addPeerAddress(host: "\(resolvedHost)", port: P2PConfig.port)
                }
                connection.cancel()
            case .failed:
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: queue)

        // Cancel after timeout
        queue.asyncAfter(deadline: .now() + 10) {
            if connection.state != .cancelled {
                connection.cancel()
            }
        }
    }

    func addPeerAddress(host: String, port: UInt16) {
        let key = "\(host):\(port)"
        guard !knownAddresses.contains(key) else { return }
        knownAddresses.insert(key)
        connectToMorePeers()
    }

    // MARK: - Connection Management

    private func connectToMorePeers() {
        let activeCount = peers.filter { $0.isConnected }.count
        let needed = P2PConfig.targetPeers - activeCount

        guard needed > 0 else { return }

        let unconnected = knownAddresses.filter { addr in
            !peers.contains { "\($0.host):\($0.port)" == addr && $0.isConnected }
        }

        for addr in unconnected.prefix(needed) {
            let parts = addr.split(separator: ":")
            guard parts.count == 2,
                  let port = UInt16(parts[1]) else { continue }

            let host = String(parts[0])
            connectToPeer(host: host, port: port)
        }
    }

    private func connectToPeer(host: String, port: UInt16) {
        let peer = PeerConnection(host: host, port: port)

        peer.onHandshakeComplete = { [weak self, weak peer] in
            guard let self, let peer else { return }
            DispatchQueue.main.async {
                self.onPeerConnected?(peer)
            }

            // Ask for more peer addresses
            peer.requestPeerAddresses()
        }

        peer.onDisconnected = { [weak self, weak peer] _ in
            guard let self, let peer else { return }
            DispatchQueue.main.async {
                self.onPeerDisconnected?(peer)
            }

            // Remove disconnected peer
            self.queue.async {
                self.peers.removeAll { $0.id == peer.id }
                // Try to reconnect
                self.queue.asyncAfter(deadline: .now() + 5) {
                    self.connectToMorePeers()
                }
            }
        }

        peer.onMessage = { [weak self] command, payload in
            guard let self else { return }

            // Handle addr messages for peer discovery
            if command == .addr, let addrMsg = AddrMessage(from: payload) {
                for addr in addrMsg.addresses {
                    if addr.services & P2PConfig.requiredServices != 0 {
                        self.addPeerAddress(host: addr.ip, port: addr.port)
                    }
                }
            }

            DispatchQueue.main.async {
                self.onMessage?(peer, command, payload)
            }
        }

        peers.append(peer)
        peer.connect()
    }

    // MARK: - Broadcasting

    /// Send a message to all connected peers
    func broadcast(command: P2PCommand, payload: Data) {
        for peer in connectedPeers {
            peer.send(command: command, payload: payload)
        }
    }

    /// Send headers request to a random connected peer
    func requestHeaders(locatorHashes: [Data]) {
        guard let peer = connectedPeers.randomElement() else { return }
        peer.requestHeaders(locatorHashes: locatorHashes)
    }

    /// Send bloom filter to all connected peers
    func sendBloomFilter(_ filter: BloomFilter) {
        for peer in connectedPeers {
            peer.sendFilterLoad(filter)
        }
    }

    /// Broadcast a raw transaction to all peers
    func broadcastTransaction(data: Data) {
        for peer in connectedPeers {
            peer.broadcastTransaction(data: data)
        }
    }
}
