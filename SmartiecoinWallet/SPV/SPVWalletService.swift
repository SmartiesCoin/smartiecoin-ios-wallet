import Foundation

/// Replaces APIService with pure P2P SPV-based data retrieval
/// No server required - connects directly to the Smartiecoin blockchain
enum SPVWalletService {
    static var client: SPVClient?

    static func startClient(watchAddress: String) -> SPVClient {
        let spv = SPVClient()
        client = spv

        Task {
            await spv.start(watchAddresses: [watchAddress])
        }

        return spv
    }

    static func stopClient() {
        client?.stop()
        client = nil
    }

    /// Fetch balance from local SPV data
    static func fetchBalance(address: String) async -> BalanceResponse {
        guard let client else {
            return BalanceResponse(balance: 0, received: 0, sent: 0)
        }

        let balance = await client.getBalance(address: address)
        let history = await client.getHistory(address: address)

        let totalReceived = history.reduce(0) { $0 + $1.received }
        let totalSent = history.reduce(0) { $0 + $1.sent }

        return BalanceResponse(
            balance: balance,
            received: totalReceived,
            sent: totalSent
        )
    }

    /// Get UTXOs from local SPV data
    static func fetchUTXOs(address: String) async -> [UTXO] {
        guard let client else { return [] }
        return await client.getUTXOs(address: address)
    }

    /// Get transaction history from local SPV data
    static func fetchHistory(address: String) async -> [HistoryTx] {
        guard let client else { return [] }
        let spvTxs = await client.getHistory(address: address)

        return spvTxs.map { tx in
            HistoryTx(
                txid: tx.txid,
                sent: tx.sent,
                received: tx.received,
                balance: 0,
                timestamp: tx.timestamp
            )
        }
    }

    /// Broadcast transaction via P2P network
    static func broadcastTransaction(hex: String) async throws -> String {
        guard let client else {
            throw WalletError.networkError("SPV client not running")
        }

        guard client.peerCount > 0 else {
            throw WalletError.networkError("Not connected to any peers")
        }

        client.broadcastTransaction(rawHex: hex)

        // Return the txid (computed from the raw hex)
        guard let txData = Data(hexString: hex) else {
            throw WalletError.transactionFailed("Invalid transaction hex")
        }

        let txid = Data(Base58.doubleSHA256(txData).reversed()).hexString
        return txid
    }

    /// Build and broadcast a transaction using SPV UTXO data
    static func sendTransaction(
        fromAddress: String,
        toAddress: String,
        amountDuffs: Int,
        privateKey: Data
    ) async throws -> (txid: String, fee: Int) {
        let utxos = await fetchUTXOs(address: fromAddress)

        guard !utxos.isEmpty else {
            throw WalletError.insufficientFunds
        }

        let result = try TransactionBuilder.buildTransaction(
            fromAddress: fromAddress,
            toAddress: toAddress,
            amountDuffs: amountDuffs,
            privateKey: privateKey,
            utxos: utxos
        )

        let txid = try await broadcastTransaction(hex: result.hex)
        return (txid, result.fee)
    }
}
