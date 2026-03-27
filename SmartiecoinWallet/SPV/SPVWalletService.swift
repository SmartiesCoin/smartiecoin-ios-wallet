import Foundation

enum SPVWalletService {
    static var client: SPVClient?

    static func fetchBalance(address: String) -> BalanceResponse {
        guard let client else {
            return BalanceResponse(balance: 0, received: 0, sent: 0)
        }
        let balance = client.getBalance(address: address)
        let history = client.getHistory(address: address)
        let totalReceived = history.reduce(0) { $0 + $1.received }
        let totalSent = history.reduce(0) { $0 + $1.sent }
        return BalanceResponse(balance: balance, received: totalReceived, sent: totalSent)
    }

    static func fetchUTXOs(address: String) -> [UTXO] {
        guard let client else { return [] }
        return client.getUTXOs(address: address)
    }

    static func fetchHistory(address: String) -> [HistoryTx] {
        guard let client else { return [] }
        return client.getHistory(address: address).map {
            HistoryTx(txid: $0.txid, sent: $0.sent, received: $0.received,
                      balance: 0, timestamp: $0.timestamp)
        }
    }

    static func broadcastTransaction(hex: String) throws -> String {
        guard let client else {
            throw WalletError.networkError("SPV client not running")
        }
        guard client.peerCount > 0 else {
            throw WalletError.networkError("Not connected to any peers")
        }
        client.broadcastTransaction(rawHex: hex)
        guard let txData = Data(hexString: hex) else {
            throw WalletError.transactionFailed("Invalid transaction hex")
        }
        return Data(Base58.doubleSHA256(txData).reversed()).hexString
    }

    static func sendTransaction(
        fromAddress: String, toAddress: String,
        amountDuffs: Int, privateKey: Data
    ) async throws -> (txid: String, fee: Int) {
        let utxos = fetchUTXOs(address: fromAddress)
        guard !utxos.isEmpty else { throw WalletError.insufficientFunds }

        let result = try TransactionBuilder.buildTransaction(
            fromAddress: fromAddress, toAddress: toAddress,
            amountDuffs: amountDuffs, privateKey: privateKey, utxos: utxos
        )
        let txid = try broadcastTransaction(hex: result.hex)
        return (txid, result.fee)
    }
}
