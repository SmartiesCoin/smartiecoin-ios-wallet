import Foundation
import Combine

/// Main SPV client coordinator - connects to the Smartiecoin P2P network,
/// syncs block headers, manages bloom filters, and tracks transactions
@Observable
final class SPVClient {
    // MARK: - Observable State

    var syncProgress: Double = 0
    var syncState: SyncState = .disconnected
    var blockHeight: Int = 0
    var networkHeight: Int = 0
    var peerCount: Int = 0
    var connectedPeers: [PeerInfo] = []
    var isSyncing = false
    var lastError: String?

    // MARK: - Internal

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
    }

    // MARK: - Lifecycle

    func start(watchAddresses: [String]) async {
        self.watchedAddresses = Set(watchAddresses)
        self.watchedPubKeyHashes = watchAddresses.compactMap {
            AddressGenerator.pubKeyHashFromAddress($0)
        }

        await MainActor.run {
            syncState = .connecting
        }

        do {
            // Build bloom filter for our addresses
            buildBloomFilter()

            // Set up peer manager callbacks
            setupPeerCallbacks()

            // Add manual peers
            for (host, port) in manualPeers {
                peerManager.addPeerAddress(host: host, port: port)
            }

            // Start connecting
            peerManager.start()

            // Start periodic sync check
            await MainActor.run {
                startSyncTimer()
            }
        } catch {
            await MainActor.run {
                syncState = .error
                lastError = error.localizedDescription
            }
        }
    }

    func stop() {
        syncTimer?.invalidate()
        syncTimer = nil
        peerManager.stop()

        Task { @MainActor in
            syncState = .disconnected
            peerCount = 0
            connectedPeers = []
            isSyncing = false
        }
    }

    func addManualPeer(host: String, port: UInt16 = P2PConfig.port) {
        manualPeers.append((host, port))
        peerManager.addPeerAddress(host: host, port: port)
    }

    func addWatchAddress(_ address: String) {
        watchedAddresses.insert(address)
        if let pubKeyHash = AddressGenerator.pubKeyHashFromAddress(address) {
            watchedPubKeyHashes.append(pubKeyHash)
        }
        // Rebuild and resend bloom filter
        buildBloomFilter()
        if let filter = bloomFilter {
            peerManager.sendBloomFilter(filter)
        }
    }

    // MARK: - Bloom Filter

    private func buildBloomFilter() {
        let elementCount = watchedPubKeyHashes.count * 2 + 1
        var filter = BloomFilter(elements: max(elementCount, 3))

        for pubKeyHash in watchedPubKeyHashes {
            // Insert the 20-byte pubkey hash
            filter.insert(pubKeyHash)
        }

        // Also insert the address strings for matching
        for address in watchedAddresses {
            filter.insert(Data(address.utf8))
        }

        self.bloomFilter = filter
    }

    // MARK: - Peer Callbacks

    private func setupPeerCallbacks() {
        peerManager.onPeerConnected = { [weak self] peer in
            guard let self else { return }

            Task { @MainActor in
                self.peerCount = self.peerManager.peerCount
                self.updatePeerList()
                self.networkHeight = Int(self.peerManager.bestPeerHeight)
            }

            // Send bloom filter to new peer
            if let filter = self.bloomFilter {
                peer.sendFilterLoad(filter)
            }

            // Start header sync
            self.requestHeaderSync()
        }

        peerManager.onPeerDisconnected = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.peerCount = self.peerManager.peerCount
                self.updatePeerList()
            }
        }

        peerManager.onMessage = { [weak self] peer, command, payload in
            guard let self else { return }

            switch command {
            case .headers:
                self.handleHeaders(payload)
            case .merkleblock:
                self.handleMerkleBlock(payload)
            case .tx:
                self.handleTransaction(payload, from: peer)
            case .inv:
                self.handleInv(payload, from: peer)
            case .reject:
                self.handleReject(payload)
            default:
                break
            }
        }
    }

    // MARK: - Header Sync

    private func requestHeaderSync() {
        Task {
            let locator = await headerStore.getBlockLocator()
            if locator.isEmpty {
                // First sync - request from genesis
                peerManager.requestHeaders(locatorHashes: [Data(repeating: 0, count: 32)])
            } else {
                peerManager.requestHeaders(locatorHashes: locator)
            }

            await MainActor.run {
                if syncState != .synchronized {
                    syncState = .syncing
                    isSyncing = true
                }
            }
        }
    }

    private func handleHeaders(_ payload: Data) {
        guard let msg = HeadersMessage(from: payload) else { return }

        Task {
            let added = await headerStore.addHeaders(msg.headers)
            let currentHeight = await headerStore.chainTipHeight
            let netHeight = Int(peerManager.bestPeerHeight)

            await MainActor.run {
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

            // If we got a full batch, request more
            if added >= P2PConfig.maxHeaders - 10 {
                requestHeaderSync()
            }
        }
    }

    // MARK: - Transaction Handling

    private func handleMerkleBlock(_ payload: Data) {
        guard let merkleBlock = MerkleBlockMessage(from: payload) else { return }

        // Extract matched transaction hashes
        guard let matchedTxids = MerkleProof.extractMatches(from: merkleBlock) else { return }

        // Request full transactions for matched hashes
        let inventory = matchedTxids.map { InvVector(type: .tx, hash: $0) }
        if !inventory.isEmpty {
            if let peer = peerManager.connectedPeers.first {
                peer.requestData(inventory)
            }
        }
    }

    private func handleTransaction(_ payload: Data, from peer: PeerConnection) {
        // Parse raw transaction and extract relevant information
        guard let txInfo = parseTransaction(payload) else { return }

        Task {
            await headerStore.addTransaction(txInfo.transaction)

            // Update UTXOs
            for utxo in txInfo.newUTXOs {
                await headerStore.addUTXO(utxo)
            }
            for spent in txInfo.spentOutputs {
                await headerStore.removeUTXO(txid: spent.txid, outputIndex: spent.outputIndex)
            }
        }
    }

    private func handleInv(_ payload: Data, from peer: PeerConnection) {
        guard let inv = InvMessage(from: payload) else { return }

        // Request merkle blocks for block announcements
        var blockRequests = [InvVector]()
        var txRequests = [InvVector]()

        for item in inv.inventory {
            switch item.type {
            case .block:
                blockRequests.append(InvVector(type: .filteredBlock, hash: item.hash))
            case .tx:
                txRequests.append(item)
            default:
                break
            }
        }

        if !blockRequests.isEmpty {
            peer.requestData(blockRequests)
            // Also sync headers
            requestHeaderSync()
        }

        if !txRequests.isEmpty {
            peer.requestData(txRequests)
        }
    }

    private func handleReject(_ payload: Data) {
        // Log rejection for debugging
        var offset = 0
        guard let msgLen = payload.readVarInt(at: &offset) else { return }
        let msgEnd = min(offset + msgLen, payload.count)
        let message = String(data: payload.subdata(in: offset..<msgEnd), encoding: .utf8) ?? "unknown"

        Task { @MainActor in
            lastError = "Rejected: \(message)"
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

        var offset = 4  // Skip version
        guard let inputCount = data.readVarInt(at: &offset) else { return nil }

        var spentOutputs: [(txid: String, outputIndex: Int)] = []

        // Parse inputs
        for _ in 0..<inputCount {
            guard offset + 36 <= data.count else { return nil }
            let prevTxid = Data(data.subdata(in: offset..<(offset + 32)).reversed()).hexString
            let prevIndex = Int(data.readUInt32LE(at: offset + 32))
            offset += 36

            guard let scriptLen = data.readVarInt(at: &offset) else { return nil }
            offset += scriptLen + 4  // Skip scriptSig + sequence

            // Check if this spends one of our UTXOs
            spentOutputs.append((txid: prevTxid, outputIndex: prevIndex))
        }

        guard let outputCount = data.readVarInt(at: &offset) else { return nil }

        var newUTXOs: [SPVUtxo] = []
        var totalReceived = 0
        var involvedAddresses: [String] = []

        // Parse outputs
        for i in 0..<outputCount {
            guard offset + 8 <= data.count else { return nil }
            let value = Int(data.readUInt64LE(at: offset))
            offset += 8

            guard let scriptLen = data.readVarInt(at: &offset) else { return nil }
            guard offset + scriptLen <= data.count else { return nil }
            let scriptPubKey = data.subdata(in: offset..<(offset + scriptLen))
            offset += scriptLen

            // Check if this output is to one of our addresses (P2PKH: 76 a9 14 <hash> 88 ac)
            if scriptPubKey.count == 25 && scriptPubKey[0] == 0x76 && scriptPubKey[1] == 0xA9 {
                let pubKeyHash = scriptPubKey.subdata(in: 3..<23)
                if watchedPubKeyHashes.contains(pubKeyHash) {
                    // Reconstruct address from pubKeyHash
                    var addressData = Data([SmartiecoinNetwork.pubKeyHash])
                    addressData.append(pubKeyHash)
                    let addr = Base58.checkEncode(addressData)

                    newUTXOs.append(SPVUtxo(
                        txid: txid,
                        outputIndex: i,
                        satoshis: value,
                        address: addr,
                        scriptPubKey: scriptPubKey.hexString,
                        blockHeight: nil
                    ))
                    totalReceived += value
                    if !involvedAddresses.contains(addr) {
                        involvedAddresses.append(addr)
                    }
                }
            }
        }

        let tx = SPVTransaction(
            txid: txid,
            blockHash: nil,
            blockHeight: nil,
            timestamp: Int(Date().timeIntervalSince1970),
            involvedAddresses: involvedAddresses,
            sent: 0,
            received: totalReceived,
            rawHex: data.hexString
        )

        return ParsedTx(transaction: tx, newUTXOs: newUTXOs, spentOutputs: spentOutputs)
    }

    // MARK: - Public Queries

    func getBalance(address: String) async -> Int {
        await headerStore.getBalance(for: address)
    }

    func getUTXOs(address: String) async -> [UTXO] {
        let spvUtxos = await headerStore.getUTXOs(for: address)
        return spvUtxos.map { utxo in
            UTXO(txid: utxo.txid, outputIndex: utxo.outputIndex,
                 satoshis: utxo.satoshis, script: utxo.scriptPubKey)
        }
    }

    func getHistory(address: String) async -> [SPVTransaction] {
        await headerStore.getTransactions(for: address)
    }

    func broadcastTransaction(rawHex: String) {
        guard let data = Data(hexString: rawHex) else { return }
        peerManager.broadcastTransaction(data: data)
    }

    // MARK: - Periodic Sync

    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.requestHeaderSync()
            Task { @MainActor in
                self.updatePeerList()
            }
        }
    }

    private func updatePeerList() {
        connectedPeers = peerManager.connectedPeers.map { peer in
            PeerInfo(
                id: peer.id,
                host: peer.host,
                port: peer.port,
                height: peer.peerHeight,
                userAgent: peer.peerVersion?.userAgent ?? "unknown",
                isConnected: peer.isConnected,
                bytesSent: peer.bytesSent,
                bytesReceived: peer.bytesReceived
            )
        }
    }

    // MARK: - Reset

    func resetChain() async {
        stop()
        await headerStore.reset()
        await MainActor.run {
            blockHeight = 0
            syncProgress = 0
            syncState = .disconnected
        }
    }
}
