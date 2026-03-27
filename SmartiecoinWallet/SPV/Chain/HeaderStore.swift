import Foundation

/// Persistent storage for block headers, transactions, and UTXOs
actor HeaderStore {
    private var headers: [Data: BlockHeader] = [:]  // hash -> header
    private var heightIndex: [Int: Data] = [:]       // height -> hash
    private var tipHash: Data?
    private var tipHeight: Int = 0

    private var confirmedTxs: [String: SPVTransaction] = [:]  // txid -> tx
    private var utxos: [String: SPVUtxo] = [:]                 // "txid:vout" -> utxo

    private let storageURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = docs.appendingPathComponent("spv_data", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        loadFromDisk()
    }

    // MARK: - Headers

    var chainTipHeight: Int { tipHeight }

    var chainTipHash: Data? { tipHash }

    func addHeaders(_ newHeaders: [BlockHeader]) -> Int {
        var added = 0
        for header in newHeaders {
            let hash = header.blockHash

            // Skip if we already have this header
            if headers[hash] != nil { continue }

            // Verify it links to our chain
            if tipHash != nil && !header.linksTo(previousHash: tipHash!) {
                // Check if it links to a known header
                if headers[header.prevHash] == nil && tipHeight > 0 {
                    continue
                }
            }

            headers[hash] = header
            tipHeight += 1
            heightIndex[tipHeight] = hash
            tipHash = hash
            added += 1
        }

        if added > 0 {
            saveToDisk()
        }

        return added
    }

    func getHeader(at height: Int) -> BlockHeader? {
        guard let hash = heightIndex[height] else { return nil }
        return headers[hash]
    }

    func getHeader(hash: Data) -> BlockHeader? {
        headers[hash]
    }

    /// Build block locator hashes for getheaders message
    func getBlockLocator() -> [Data] {
        var locator = [Data]()
        var height = tipHeight
        var step = 1

        while height > 0 {
            if let hash = heightIndex[height] {
                locator.append(hash)
            }

            if locator.count >= 10 {
                step *= 2
            }
            height -= step
        }

        // Always include genesis
        if let genesisHash = heightIndex[0] {
            if locator.last != genesisHash {
                locator.append(genesisHash)
            }
        }

        return locator
    }

    // MARK: - Transactions

    func addTransaction(_ tx: SPVTransaction) {
        confirmedTxs[tx.txid] = tx
        saveToDisk()
    }

    func getTransactions(for address: String) -> [SPVTransaction] {
        confirmedTxs.values
            .filter { $0.involvedAddresses.contains(address) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func getTransaction(txid: String) -> SPVTransaction? {
        confirmedTxs[txid]
    }

    // MARK: - UTXOs

    func addUTXO(_ utxo: SPVUtxo) {
        let key = "\(utxo.txid):\(utxo.outputIndex)"
        utxos[key] = utxo
        saveToDisk()
    }

    func removeUTXO(txid: String, outputIndex: Int) {
        let key = "\(txid):\(outputIndex)"
        utxos.removeValue(forKey: key)
        saveToDisk()
    }

    func getUTXOs(for address: String) -> [SPVUtxo] {
        utxos.values.filter { $0.address == address }
    }

    func getBalance(for address: String) -> Int {
        getUTXOs(for: address).reduce(0) { $0 + $1.satoshis }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let state = SPVState(
            tipHeight: tipHeight,
            tipHash: tipHash?.hexString,
            headers: Array(headers.values),
            transactions: Array(confirmedTxs.values),
            utxos: Array(utxos.values)
        )

        if let data = try? JSONEncoder().encode(state) {
            let url = storageURL.appendingPathComponent("spv_state.json")
            try? data.write(to: url)
        }
    }

    private func loadFromDisk() {
        let url = storageURL.appendingPathComponent("spv_state.json")
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SPVState.self, from: data) else { return }

        // Rebuild header index
        for header in state.headers {
            let hash = header.blockHash
            headers[hash] = header
        }

        tipHeight = state.tipHeight
        if let hashHex = state.tipHash {
            tipHash = Data(hexString: hashHex)
        }

        // Rebuild height index from headers
        rebuildHeightIndex()

        // Load transactions and UTXOs
        for tx in state.transactions {
            confirmedTxs[tx.txid] = tx
        }
        for utxo in state.utxos {
            let key = "\(utxo.txid):\(utxo.outputIndex)"
            utxos[key] = utxo
        }
    }

    private func rebuildHeightIndex() {
        guard let tip = tipHash else { return }
        var current: Data? = tip
        var height = tipHeight

        while let hash = current, let header = headers[hash], height >= 0 {
            heightIndex[height] = hash
            current = header.prevHash
            height -= 1
        }
    }

    func reset() {
        headers.removeAll()
        heightIndex.removeAll()
        confirmedTxs.removeAll()
        utxos.removeAll()
        tipHash = nil
        tipHeight = 0

        let url = storageURL.appendingPathComponent("spv_state.json")
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Models

struct SPVTransaction: Codable, Identifiable {
    let txid: String
    let blockHash: String?
    let blockHeight: Int?
    let timestamp: Int
    let involvedAddresses: [String]
    let sent: Int      // total sent from our addresses
    let received: Int  // total received to our addresses
    let rawHex: String?

    var id: String { txid }

    var isReceive: Bool { received > sent }
    var netAmount: Int { isReceive ? (received - sent) : (sent - received) }
}

struct SPVUtxo: Codable {
    let txid: String
    let outputIndex: Int
    let satoshis: Int
    let address: String
    let scriptPubKey: String
    let blockHeight: Int?
}

struct SPVState: Codable {
    let tipHeight: Int
    let tipHash: String?
    let headers: [BlockHeader]
    let transactions: [SPVTransaction]
    let utxos: [SPVUtxo]
}
