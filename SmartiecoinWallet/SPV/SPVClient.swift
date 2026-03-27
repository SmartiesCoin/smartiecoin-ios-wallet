import Foundation
import Combine

/// Main SPV client coordinator
final class SPVClient: ObservableObject {
    @Published var syncProgress: Double = 0
    @Published var syncState: SyncState = .disconnected
    @Published var blockHeight: Int = 0
    @Published var networkHeight: Int = 0
    @Published var peerCount: Int = 0
    @Published var connectedPeers: [PeerInfo] = []
    @Published var isSyncing = false
    @Published var lastError: String?

    private let peerManager = PeerManager()
    private let headerStore = HeaderStore()
    private var bloomFilter: BloomFilter?
    private var watchedAddresses: Set<String> = []
    private var watchedPubKeyHashes: [Data] = []
    private var manualPeers: [(String, UInt16)] = []
    private var syncTimer: Timer?

    enum SyncState: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting..."
        case syncing = "Syncing Headers..."
        case synchronized = "Synchronized"
        case error = "Error"
    }

    struct PeerInfo: Identifiable {
        let id: UUID
        let host: String
        let port: UInt16
        let height: Int32
        let userAgent: String
        let isConnected: Bool
        let bytesSent: Int
        let bytesReceived: Int
        let status: String
    }

    // MARK: - Lifecycle (call from main thread)

    func start(watchAddresses: [String]) {
        watchedAddresses = Set(watchAddresses)
        watchedPubKeyHashes = watchAddresses.compactMap {
            AddressGenerator.pubKeyHashFromAddress($0)
        }

        syncState = .connecting
        buildBloomFilter()
        setupPeerCallbacks()

        for (host, port) in manualPeers {
            peerManager.addPeerAddress(host: host, port: port)
        }

        peerManager.start()
        startSyncTimer()
    }

    func stop() {
        syncTimer?.invalidate()
        syncTimer = nil
        peerManager.stop()
        syncState = .disconnected
        peerCount = 0
        connectedPeers = []
        isSyncing = false
    }

    func addManualPeer(host: String, port: UInt16 = P2PConfig.port) {
        manualPeers.append((host, port))
        peerManager.addPeerAddress(host: host, port: port)
    }

    // MARK: - Bloom Filter

    private func buildBloomFilter() {
        let elementCount = watchedPubKeyHashes.count * 2 + 1
        var filter = BloomFilter(elements: max(elementCount, 3))
        for pubKeyHash in watchedPubKeyHashes {
            filter.insert(pubKeyHash)
        }
        for address in watchedAddresses {
            filter.insert(Data(address.utf8))
        }
        bloomFilter = filter
    }

    // MARK: - Peer Callbacks

    private func setupPeerCallbacks() {
        peerManager.onPeerConnected = { [weak self] peer in
            guard let self else { return }
            DispatchQueue.main.async {
                self.peerCount = self.peerManager.peerCount
                self.updatePeerList()
                self.networkHeight = Int(self.peerManager.bestPeerHeight)
            }
            if let filter = self.bloomFilter {
                peer.sendFilterLoad(filter)
            }
            self.requestHeaderSync()
        }

        peerManager.onPeerDisconnected = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.peerCount = self.peerManager.peerCount
                self.updatePeerList()
            }
        }

        peerManager.onMessage = { [weak self] peer, command, payload in
            guard let self else { return }
            switch command {
            case .headers:   self.handleHeaders(payload)
            case .merkleblock: self.handleMerkleBlock(payload)
            case .tx:        self.handleTransaction(payload)
            case .inv:       self.handleInv(payload, from: peer)
            case .reject:    self.handleReject(payload)
            default: break
            }
        }
    }

    // MARK: - Header Sync

    private func requestHeaderSync() {
        let locator = headerStore.getBlockLocator()
        if locator.isEmpty {
            peerManager.requestHeaders(locatorHashes: [Data(repeating: 0, count: 32)])
        } else {
            peerManager.requestHeaders(locatorHashes: locator)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.syncState != .synchronized else { return }
            self.syncState = .syncing
            self.isSyncing = true
        }
    }

    private func handleHeaders(_ payload: Data) {
        guard let msg = HeadersMessage(from: payload) else { return }

        let added = headerStore.addHeaders(msg.headers)
        let currentHeight = headerStore.chainTipHeight
        let netHeight = Int(peerManager.bestPeerHeight)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.blockHeight = currentHeight
            self.networkHeight = max(netHeight, currentHeight)
            if netHeight > 0 {
                self.syncProgress = min(Double(currentHeight) / Double(netHeight), 1.0)
            }
            if currentHeight >= netHeight - 1 {
                self.syncState = .synchronized
                self.isSyncing = false
            }
        }

        if added >= P2PConfig.maxHeaders - 10 {
            requestHeaderSync()
        }
    }

    // MARK: - Transactions

    private func handleMerkleBlock(_ payload: Data) {
        guard let merkleBlock = MerkleBlockMessage(from: payload) else { return }
        guard let matchedTxids = MerkleProof.extractMatches(from: merkleBlock) else { return }
        let inventory = matchedTxids.map { InvVector(type: .tx, hash: $0) }
        if !inventory.isEmpty, let peer = peerManager.connectedPeers.first {
            peer.requestData(inventory)
        }
    }

    private func handleTransaction(_ payload: Data) {
        guard let txInfo = parseTransaction(payload) else { return }
        headerStore.addTransaction(txInfo.transaction)
        for utxo in txInfo.newUTXOs { headerStore.addUTXO(utxo) }
        for spent in txInfo.spentOutputs {
            headerStore.removeUTXO(txid: spent.txid, outputIndex: spent.outputIndex)
        }
    }

    private func handleInv(_ payload: Data, from peer: PeerConnection) {
        guard let inv = InvMessage(from: payload) else { return }
        var blockRequests = [InvVector]()
        var txRequests = [InvVector]()

        for item in inv.inventory {
            switch item.type {
            case .block:  blockRequests.append(InvVector(type: .filteredBlock, hash: item.hash))
            case .tx:     txRequests.append(item)
            default: break
            }
        }

        if !blockRequests.isEmpty {
            peer.requestData(blockRequests)
            requestHeaderSync()
        }
        if !txRequests.isEmpty {
            peer.requestData(txRequests)
        }
    }

    private func handleReject(_ payload: Data) {
        var offset = 0
        guard let msgLen = payload.readVarInt(at: &offset) else { return }
        let msgEnd = min(offset + msgLen, payload.count)
        let message = String(data: payload.subdata(in: offset..<msgEnd), encoding: .utf8) ?? "unknown"
        DispatchQueue.main.async { [weak self] in
            self?.lastError = "Rejected: \(message)"
        }
    }

    // MARK: - Transaction Parsing

    private struct ParsedTx {
        let transaction: SPVTransaction
        let newUTXOs: [SPVUtxo]
        let spentOutputs: [(txid: String, outputIndex: Int)]
    }

    private func parseTransaction(_ data: Data) -> ParsedTx? {
        guard data.count > 10 else { return nil }
        let txid = Data(Base58.doubleSHA256(data).reversed()).hexString

        var offset = 4
        guard let inputCount = data.readVarInt(at: &offset) else { return nil }

        var spentOutputs: [(txid: String, outputIndex: Int)] = []
        for _ in 0..<inputCount {
            guard offset + 36 <= data.count else { return nil }
            let prevTxid = Data(data.subdata(in: offset..<(offset + 32)).reversed()).hexString
            let prevIndex = Int(data.readUInt32LE(at: offset + 32))
            offset += 36
            guard let scriptLen = data.readVarInt(at: &offset) else { return nil }
            offset += scriptLen + 4
            spentOutputs.append((txid: prevTxid, outputIndex: prevIndex))
        }

        guard let outputCount = data.readVarInt(at: &offset) else { return nil }
        var newUTXOs: [SPVUtxo] = []
        var totalReceived = 0
        var involvedAddresses: [String] = []

        for i in 0..<outputCount {
            guard offset + 8 <= data.count else { return nil }
            let value = Int(data.readUInt64LE(at: offset))
            offset += 8
            guard let scriptLen = data.readVarInt(at: &offset) else { return nil }
            guard offset + scriptLen <= data.count else { return nil }
            let scriptPubKey = data.subdata(in: offset..<(offset + scriptLen))
            offset += scriptLen

            if scriptPubKey.count == 25 && scriptPubKey[0] == 0x76 && scriptPubKey[1] == 0xA9 {
                let pubKeyHash = scriptPubKey.subdata(in: 3..<23)
                if watchedPubKeyHashes.contains(pubKeyHash) {
                    var addressData = Data([SmartiecoinNetwork.pubKeyHash])
                    addressData.append(pubKeyHash)
                    let addr = Base58.checkEncode(addressData)

                    newUTXOs.append(SPVUtxo(
                        txid: txid, outputIndex: i, satoshis: value,
                        address: addr, scriptPubKey: scriptPubKey.hexString, blockHeight: nil
                    ))
                    totalReceived += value
                    if !involvedAddresses.contains(addr) { involvedAddresses.append(addr) }
                }
            }
        }

        let tx = SPVTransaction(
            txid: txid, blockHash: nil, blockHeight: nil,
            timestamp: Int(Date().timeIntervalSince1970),
            involvedAddresses: involvedAddresses,
            sent: 0, received: totalReceived, rawHex: data.hexString
        )
        return ParsedTx(transaction: tx, newUTXOs: newUTXOs, spentOutputs: spentOutputs)
    }

    // MARK: - Public Queries

    func getBalance(address: String) -> Int {
        headerStore.getBalance(for: address)
    }

    func getUTXOs(address: String) -> [UTXO] {
        headerStore.getUTXOs(for: address).map {
            UTXO(txid: $0.txid, outputIndex: $0.outputIndex,
                 satoshis: $0.satoshis, script: $0.scriptPubKey)
        }
    }

    func getHistory(address: String) -> [SPVTransaction] {
        headerStore.getTransactions(for: address)
    }

    func broadcastTransaction(rawHex: String) {
        guard let data = Data(hexString: rawHex) else { return }
        peerManager.broadcastTransaction(data: data)
    }

    // MARK: - Timer

    private func startSyncTimer() {
        // Update peer list frequently for live status
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.updatePeerList() }
        }

        // Sync headers less frequently
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.requestHeaderSync()
        }
    }

    private func updatePeerList() {
        // Show ALL peers including those still connecting
        connectedPeers = peerManager.allPeers.map {
            PeerInfo(id: $0.id, host: $0.host, port: $0.port, height: $0.peerHeight,
                     userAgent: $0.peerVersion?.userAgent ?? "",
                     isConnected: $0.isHandshakeComplete, bytesSent: $0.bytesSent,
                     bytesReceived: $0.bytesReceived, status: $0.statusMessage)
        }
    }

    func resetChain() {
        stop()
        headerStore.reset()
        blockHeight = 0
        syncProgress = 0
        syncState = .disconnected
    }
}
