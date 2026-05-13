import Foundation

/// Thread-safe storage for block headers, transactions, and UTXOs.
/// Headers are indexed by height. The tip's yespower hash is computed once per batch
/// (yespower is too expensive to compute per header).
final class HeaderStore {
    private let lock = NSLock()
    private var headersByHeight: [Int: BlockHeader] = [:]
    private var _tipHeight: Int = 0
    private var _tipHash: Data?

    private var confirmedTxs: [String: SPVTransaction] = [:]
    private var utxos: [String: SPVUtxo] = [:]

    private let storageURL: URL
    private static let storageVersion = 2

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = docs.appendingPathComponent("spv_data", isDirectory: true)
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        loadFromDisk()
    }

    var chainTipHeight: Int {
        lock.lock()
        defer { lock.unlock() }
        return _tipHeight
    }

    var chainTipHash: Data? {
        lock.lock()
        defer { lock.unlock() }
        return _tipHash
    }

    func addHeaders(_ newHeaders: [BlockHeader]) -> Int {
        guard !newHeaders.isEmpty else { return 0 }

        lock.lock()

        if let currentTip = _tipHash {
            guard newHeaders[0].prevHash == currentTip else {
                lock.unlock()
                return 0
            }
        }

        var added = 0
        for header in newHeaders {
            _tipHeight += 1
            headersByHeight[_tipHeight] = header
            added += 1
        }

        let lastHeader = newHeaders.last!
        lock.unlock()

        let newTipHash = lastHeader.blockHash

        lock.lock()
        _tipHash = newTipHash
        lock.unlock()

        if added > 0 { saveToDisk() }
        return added
    }

    func getBlockLocator() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        if let tip = _tipHash { return [tip] }
        return []
    }

    func header(at height: Int) -> BlockHeader? {
        lock.lock()
        defer { lock.unlock() }
        return headersByHeight[height]
    }

    func addTransaction(_ tx: SPVTransaction) {
        lock.lock()
        // If an outgoing tx was previously recorded optimistically (sent > 0),
        // preserve its sent amount so self-sends and normal sends keep showing
        // as "Sent" after the network version arrives and gets re-parsed.
        if let existing = confirmedTxs[tx.txid], existing.sent > 0 {
            let merged = SPVTransaction(
                txid: tx.txid,
                blockHash: tx.blockHash ?? existing.blockHash,
                blockHeight: tx.blockHeight ?? existing.blockHeight,
                timestamp: existing.timestamp,
                involvedAddresses: existing.involvedAddresses,
                sent: existing.sent,
                received: existing.received,
                rawHex: tx.rawHex ?? existing.rawHex
            )
            confirmedTxs[tx.txid] = merged
        } else {
            confirmedTxs[tx.txid] = tx
        }
        lock.unlock()
        saveToDisk()
    }

    func getTransactions(for address: String) -> [SPVTransaction] {
        lock.lock()
        defer { lock.unlock() }
        return confirmedTxs.values
            .filter { $0.involvedAddresses.contains(address) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func addUTXO(_ utxo: SPVUtxo) {
        lock.lock()
        utxos["\(utxo.txid):\(utxo.outputIndex)"] = utxo
        lock.unlock()
        saveToDisk()
    }

    func removeUTXO(txid: String, outputIndex: Int) {
        lock.lock()
        utxos.removeValue(forKey: "\(txid):\(outputIndex)")
        lock.unlock()
        saveToDisk()
    }

    func getUTXOs(for address: String) -> [SPVUtxo] {
        lock.lock()
        defer { lock.unlock() }
        return utxos.values.filter { $0.address == address }
    }

    func getBalance(for address: String) -> Int {
        getUTXOs(for: address).reduce(0) { $0 + $1.satoshis }
    }

    func reset() {
        lock.lock()
        headersByHeight.removeAll()
        confirmedTxs.removeAll()
        utxos.removeAll()
        _tipHash = nil
        _tipHeight = 0
        lock.unlock()

        let url = storageURL.appendingPathComponent("spv_state.json")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        lock.lock()
        let orderedHeaders = (1..._tipHeight).compactMap { headersByHeight[$0] }
        let state = SPVState(
            version: HeaderStore.storageVersion,
            tipHeight: _tipHeight,
            tipHash: _tipHash?.hexString,
            headers: orderedHeaders,
            transactions: Array(confirmedTxs.values),
            utxos: Array(utxos.values)
        )
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [storageURL] in
            if let data = try? JSONEncoder().encode(state) {
                let url = storageURL.appendingPathComponent("spv_state.json")
                try? data.write(to: url)
            }
        }
    }

    private func loadFromDisk() {
        let url = storageURL.appendingPathComponent("spv_state.json")
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SPVState.self, from: data) else { return }

        // Discard chain state from older incompatible format
        guard (state.version ?? 1) >= HeaderStore.storageVersion else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        for (i, header) in state.headers.enumerated() {
            headersByHeight[i + 1] = header
        }
        _tipHeight = state.tipHeight
        if let hashHex = state.tipHash {
            _tipHash = Data(hexString: hashHex)
        }

        for tx in state.transactions { confirmedTxs[tx.txid] = tx }
        for utxo in state.utxos { utxos["\(utxo.txid):\(utxo.outputIndex)"] = utxo }
    }
}

// MARK: - Models

struct SPVTransaction: Codable, Identifiable {
    let txid: String
    let blockHash: String?
    let blockHeight: Int?
    let timestamp: Int
    let involvedAddresses: [String]
    let sent: Int
    let received: Int
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
    let version: Int?
    let tipHeight: Int
    let tipHash: String?
    let headers: [BlockHeader]
    let transactions: [SPVTransaction]
    let utxos: [SPVUtxo]
}
