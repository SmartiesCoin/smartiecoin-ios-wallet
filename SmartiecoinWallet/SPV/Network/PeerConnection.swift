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

    // State
    private(set) var isConnected = false
    private(set) var isHandshakeComplete = false
    private(set) var peerVersion: VersionMessage?
    private(set) var peerHeight: Int32 = 0
    private(set) var lastSeen = Date()
    private(set) var bytesSent: Int = 0
    private(set) var bytesReceived: Int = 0

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

    func connect() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: nwPort
        )

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        connection = NWConnection(to: endpoint, using: params)

        connection?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.isConnected = true
                self.onConnected?()
                self.startReceiving()
                self.sendVersion()
            case .failed(let error):
                self.isConnected = false
                self.onDisconnected?(error)
            case .cancelled:
                self.isConnected = false
                self.onDisconnected?(nil)
            default:
                break
            }
        }

        connection?.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        isHandshakeComplete = false
    }

    // MARK: - Sending Messages

    func send(command: P2PCommand, payload: Data = Data()) {
        let message = P2PSerializer.buildMessage(command: command, payload: payload)
        bytesSent += message.count

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
                self.bytesReceived += data.count
                self.lastSeen = Date()
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

            let payload = buffer.subdata(in: P2PMessageHeader.size..<totalSize)

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
        default:
            // Forward to delegate
            onMessage?(command, payload)
        }
    }

    private func handleVersion(_ payload: Data) {
        guard let version = VersionMessage(from: payload) else { return }
        peerVersion = version
        peerHeight = version.startHeight
        send(command: .verack)
    }

    private func handleVerack() {
        isHandshakeComplete = true
        // Request peer to send headers directly (sendheaders BIP130)
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
