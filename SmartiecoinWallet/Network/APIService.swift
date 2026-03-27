import Foundation

struct BalanceResponse: Codable {
    let balance: Int
    let received: Int
    let sent: Int
}

struct HistoryTx: Codable, Identifiable {
    let txid: String
    let sent: Int
    let received: Int
    let balance: Int
    let timestamp: Int

    var id: String { txid }

    var isReceive: Bool { received > sent }

    var netAmount: Int {
        isReceive ? (received - sent) : (sent - received)
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

struct BroadcastResponse: Codable {
    let txid: String
}

struct ExplorerUTXO: Codable {
    let txid: String
    let vout: Int
    let amount: Double
    let scriptPubKey: String
}

struct RawTxResponse: Codable {
    let hex: String
}

enum APIService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private static func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let url = URL(string: "\(SmartiecoinNetwork.apiBase)\(path)") else {
            throw WalletError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalletError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMsg = errorBody["error"] {
                throw WalletError.networkError(errorMsg)
            }
            throw WalletError.networkError("HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    static func fetchBalance(address: String) async throws -> BalanceResponse {
        try await request("/balance/\(address)")
    }

    static func fetchUTXOs(address: String) async throws -> [UTXO] {
        let raw: [ExplorerUTXO] = try await request("/utxos/\(address)")
        return raw.map { utxo in
            UTXO(
                txid: utxo.txid,
                outputIndex: utxo.vout,
                satoshis: Int(round(utxo.amount * Double(SmartiecoinNetwork.coin))),
                script: utxo.scriptPubKey
            )
        }
    }

    static func fetchHistory(address: String) async throws -> [HistoryTx] {
        try await request("/history/\(address)")
    }

    static func broadcastTransaction(hex: String) async throws -> String {
        let body = try JSONEncoder().encode(["hex": hex])
        let result: BroadcastResponse = try await request("/broadcast", method: "POST", body: body)
        return result.txid
    }

    static func fetchRawTx(txid: String) async throws -> String {
        let result: RawTxResponse = try await request("/rawtx/\(txid)")
        return result.hex
    }
}
