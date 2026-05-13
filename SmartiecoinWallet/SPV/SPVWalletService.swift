import Foundation

/// Node wallet service. Queries the Smartiecoin explorer API as the source of
/// truth for balance/history/UTXOs/broadcast, while keeping `SPVClient` running
/// in the background for the Network Status view (peer list, chain sync).
/// This avoids the "ghost transaction" problem that pure P2P broadcast had:
/// peers silently drop unsolicited tx messages, so the only way to know a tx
/// actually hit the mempool is to hear it back from the indexer.
enum SPVWalletService {
    static var client: SPVClient?

    static func fetchBalance(address: String) async -> BalanceResponse {
        (try? await APIService.fetchBalance(address: address))
            ?? BalanceResponse(balance: 0, received: 0, sent: 0)
    }

    static func fetchUTXOs(address: String) async -> [UTXO] {
        (try? await APIService.fetchUTXOs(address: address)) ?? []
    }

    static func fetchHistory(address: String) async -> [HistoryTx] {
        (try? await APIService.fetchHistory(address: address)) ?? []
    }

    static func sendTransaction(
        fromAddress: String, toAddress: String,
        amountDuffs: Int, privateKey: Data
    ) async throws -> (txid: String, fee: Int) {
        let utxos = try await APIService.fetchUTXOs(address: fromAddress)
        guard !utxos.isEmpty else { throw WalletError.insufficientFunds }

        let result = try TransactionBuilder.buildTransaction(
            fromAddress: fromAddress, toAddress: toAddress,
            amountDuffs: amountDuffs, privateKey: privateKey, utxos: utxos
        )

        // Broadcast via the indexer (authoritative, returns txid on success)
        // and also push it over our P2P peers as a bonus relay.
        let txid = try await APIService.broadcastTransaction(hex: result.hex)
        client?.broadcastTransaction(rawHex: result.hex)

        return (txid, result.fee)
    }
}
