import Foundation
import Network

/// Manages a single TCP connection to a Smartiecoin P2P node
final class PeerConnection: @unchecked Sendable {
    let id = UUID()
    let host: String
    let port: UInt16

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.smartiecoin.peer")
    private var buffer = Data()
    private let stateLock = NSLock()

    // State (accessed via stateLock for thread safety)
    private var _isConnected = false
    private var _isHandshakeComplete = false
    private var _peerVersion: VersionMessage?
    private var _peerHeight: Int32 = 0
    private var _lastSeen = Date()
    private var _bytesSent: Int = 0
    private var _bytesReceived: Int = 0
    // Raw tx bytes we've announced via `inv` so we can serve them when the
    // peer replies with `getdata`. Keyed by txid in wire (internal) byte order.
    private var pendingTxs: [Data: Data] = [:]

    var isConnected: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _isConnected
    }
    var isHandshakeComplete: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _isHandshakeComplete
    }
    var peerVersion: VersionMessage? {
        stateLock.lock(); defer { stateLock.unlock() }
        return _peerVersion
    }
    var peerHeight: Int32 {
        stateLock.lock(); defer { stateLock.unlock() }
        return _peerHeight
    }
    var lastSeen: Date {
        stateLock.lock(); defer { stateLock.unlock() }
        return _lastSeen
    }
    var bytesSent: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return _bytesSent
    }
    var bytesReceived: Int {
        stateLock.lock(); defer { stateLock.unlock() }
        return _bytesReceived
    }

    // Callbacks
    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    var onMessage: ((P2PCommand, Data) -> Void)?
    var onHandshakeComplete: (() -> Void)?

    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    // MARK: - Connection Lifecycle

    // Status for debugging
    private(set) var statusMessage: String = "init"

    func connect() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            statusMessage = "invalid port"
            return
        }
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: nwPort
        )

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        connection = NWConnection(to: endpoint, using: params)
        statusMessage = "connecting..."

        connection?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .setup:
                self.statusMessage = "setup"
            case .preparing:
                self.statusMessage = "preparing"
            case .ready:
                self.stateLock.lock()
                self._isConnected = true
                self.stateLock.unlock()
                self.statusMessage = "TCP connected, sending version..."
                self.onConnected?()
                self.startReceiving()
                self.sendVersion()
            case .waiting(let error):
                self.statusMessage = "waiting: \(error)"
            case .failed(let error):
                self.stateLock.lock()
                self._isConnected = false
                self.stateLock.unlock()
                self.statusMessage = "failed: \(error)"
                self.onDisconnected?(error)
            case .cancelled:
                self.stateLock.lock()
                self._isConnected = false
                self.stateLock.unlock()
                self.statusMessage = "cancelled"
                self.onDisconnected?(nil)
            @unknown default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        stateLock.lock()
        _isConnected = false
        _isHandshakeComplete = false
        stateLock.unlock()
    }

    // MARK: - Sending Messages

    func send(command: P2PCommand, payload: Data = Data()) {
        let message = P2PSerializer.buildMessage(command: command, payload: payload)
        stateLock.lock()
        _bytesSent += message.count
        stateLock.unlock()

        connection?.send(content: message, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.disconnect()
                self?.onDisconnected?(error)
            }
        })
    }

    private func sendVersion() {
        let msg = VersionMessage.create(
            peerIP: host,
            peerPort: port,
            blockHeight: 0  // Will be updated after initial sync
        )
        send(command: .version, payload: msg.serialized)
    }

    // MARK: - Receiving Messages

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data {
                self.buffer.append(data)
                self.stateLock.lock()
                self._bytesReceived += data.count
                self._lastSeen = Date()
                self.stateLock.unlock()
                self.processBuffer()
            }

            if isComplete {
                self.disconnect()
                self.onDisconnected?(nil)
            } else if let error {
                self.disconnect()
                self.onDisconnected?(error)
            } else {
                self.startReceiving()
            }
        }
    }

    private func processBuffer() {
        while buffer.count >= P2PMessageHeader.size {
            // Read header
            guard let header = P2PMessageHeader(from: buffer) else {
                // Invalid header - skip a byte and try again
                buffer.removeFirst()
                continue
            }

            // Verify magic
            guard header.magic == P2PConfig.magic else {
                buffer.removeFirst()
                continue
            }

            let totalSize = P2PMessageHeader.size + Int(header.payloadLength)
            guard buffer.count >= totalSize else {
                break  // Need more data
            }

            let s = buffer.startIndex
            let payload = buffer.subdata(in: (s + P2PMessageHeader.size)..<(s + totalSize))

            // Verify checksum
            if P2PSerializer.verifyChecksum(payload: payload, expected: header.checksum) {
                handleMessage(command: header.command, payload: payload)
            }

            buffer.removeFirst(totalSize)
        }
    }

    // MARK: - Message Handling

    private func handleMessage(command: P2PCommand, payload: Data) {
        switch command {
        case .version:
            handleVersion(payload)
        case .verack:
            handleVerack()
        case .ping:
            handlePing(payload)
        case .getdata:
            handleGetData(payload)
            onMessage?(command, payload)
        default:
            // Forward to delegate
            onMessage?(command, payload)
        }
    }

    private func handleGetData(_ payload: Data) {
        guard let inv = InvMessage(from: payload) else { return }
        for item in inv.inventory where item.type == .tx {
            stateLock.lock()
            let tx = pendingTxs[item.hash]
            stateLock.unlock()
            if let tx {
                send(command: .tx, payload: tx)
            }
        }
    }

    private func handleVersion(_ payload: Data) {
        guard let version = VersionMessage(from: payload) else {
            statusMessage = "bad version msg (\(payload.count) bytes)"
            return
        }
        stateLock.lock()
        _peerVersion = version
        _peerHeight = version.startHeight
        stateLock.unlock()
        statusMessage = "got version v\(version.protocolVersion) h\(version.startHeight), sending verack"
        send(command: .verack)
    }

    private func handleVerack() {
        stateLock.lock()
        _isHandshakeComplete = true
        stateLock.unlock()
        statusMessage = "handshake complete"
        send(command: .sendheaders)
        onHandshakeComplete?()
    }

    private func handlePing(_ payload: Data) {
        guard let ping = PingMessage(from: payload) else { return }
        let pong = PingMessage(nonce: ping.nonce)
        send(command: .pong, payload: pong.serialized)
    }

    // MARK: - High-Level Operations

    func requestHeaders(locatorHashes: [Data]) {
        let msg = GetHeadersMessage.create(locatorHashes: locatorHashes)
        send(command: .getHeaders, payload: msg.serialized)
    }

    func sendFilterLoad(_ filter: BloomFilter) {
        let msg = filter.toFilterLoadMessage()
        send(command: .filterload, payload: msg.serialized)
    }

    func requestData(_ inventory: [InvVector]) {
        let msg = InvMessage(inventory: inventory)
        send(command: .getdata, payload: msg.serialized)
    }

    func broadcastTransaction(data: Data) {
        // Txid on the wire is the double-SHA256 of the raw tx in natural
        // (internal) byte order — NOT the display-reversed hex.
        let txidInternal = Base58.doubleSHA256(data)

        stateLock.lock()
        pendingTxs[txidInternal] = data
        stateLock.unlock()

        // Announce via inv so standards-compliant peers request it with getdata.
        let invMsg = InvMessage(inventory: [InvVector(type: .tx, hash: txidInternal)])
        send(command: .inv, payload: invMsg.serialized)

        // Also push the raw tx; most Bitcoin/Dash peers accept unsolicited tx,
        // and this covers peers that don't follow up on the inv.
        send(command: .tx, payload: data)
    }

    func requestPeerAddresses() {
        send(command: .getaddr)
    }
}

extension PeerConnection: Hashable {
    static func == (lhs: PeerConnection, rhs: PeerConnection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
