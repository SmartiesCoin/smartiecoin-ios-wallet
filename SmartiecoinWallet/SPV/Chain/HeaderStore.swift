import Foundation

/// Thread-safe storage for block headers, transactions, and UTXOs
final class HeaderStore {
    private let lock = NSLock()
    private var headers: [Data: BlockHeader] = [:]
    private var heightIndex: [Int: Data] = [:]
    private var tipHash: Data?
    private var _tipHeight: Int = 0

    private var confirmedTxs: [String: SPVTransaction] = [:]
    private var utxos: [String: SPVUtxo] = [:]

    private let storageURL: URL

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
        return tipHash
    }

    func addHeaders(_ newHeaders: [BlockHeader]) -> Int {
        lock.lock()
        defer { lock.unlock() }

        var added = 0
        for header in newHeaders {
            let hash = header.blockHash
            if headers[hash] != nil { continue }

            if tipHash != nil && !header.linksTo(previousHash: tipHash!) {
                if headers[header.prevHash] == nil && _tipHeight > 0 {
                    continue
                }
            }

            headers[hash] = header
            _tipHeight += 1
            heightIndex[_tipHeight] = hash
            tipHash = hash
            added += 1
        }

        if added > 0 { saveToDisk() }
        return added
    }

    func getBlockLocator() -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        var locator = [Data]()
        var height = _tipHeight
        var step = 1

        while height > 0 {
            if let hash = heightIndex[height] {
                locator.append(hash)
            }
            if locator.count >= 10 { step *= 2 }
            height -= step
        }

        if let genesisHash = heightIndex[0], locator.last != genesisHash {
            locator.append(genesisHash)
        }

        return locator
    }

    func addTransaction(_ tx: SPVTransaction) {
        lock.lock()
        confirmedTxs[tx.txid] = tx
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
        headers.removeAll()
        heightIndex.removeAll()
        confirmedTxs.removeAll()
        utxos.removeAll()
        tipHash = nil
        _tipHeight = 0
        lock.unlock()

        let url = storageURL.appendingPathComponent("spv_state.json")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        lock.lock()
        let state = SPVState(
            tipHeight: _tipHeight,
            tipHash: tipHash?.hexString,
            headers: Array(headers.values),
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

        for header in state.headers {
            headers[header.blockHash] = header
        }
        _tipHeight = state.tipHeight
        if let hashHex = state.tipHash {
            tipHash = Data(hexString: hashHex)
        }
        rebuildHeightIndex()

        for tx in state.transactions { confirmedTxs[tx.txid] = tx }
        for utxo in state.utxos { utxos["\(utxo.txid):\(utxo.outputIndex)"] = utxo }
    }

    private func rebuildHeightIndex() {
        guard let tip = tipHash else { return }
        var current: Data? = tip
        var height = _tipHeight

        while let hash = current, let header = headers[hash], height >= 0 {
            heightIndex[height] = hash
            current = header.prevHash
            height -= 1
        }
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
    let tipHeight: Int
    let tipHash: String?
    let headers: [BlockHeader]
    let transactions: [SPVTransaction]
    let utxos: [SPVUtxo]
}
