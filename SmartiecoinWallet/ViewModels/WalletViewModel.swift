import Foundation
import SwiftUI

enum AppScreen: Equatable {
    case loading
    case landing
    case create
    case backup
    case importWallet
    case unlock
    case dashboard
    case send
    case receive
    case history
    case networkStatus
}

@Observable
final class WalletViewModel {
    var screen: AppScreen = .loading
    var walletData: WalletData?
    var privateKey: Data?
    var mnemonic: String?
    var balance: BalanceResponse?
    var error: String?
    var loading = false

    // SPV Client
    var spvClient = SPVClient()

    private var balanceTimer: Timer?

    init() {
        loadWallet()
    }

    func loadWallet() {
        if let data = WalletService.loadWallet() {
            walletData = data
            screen = .unlock
        } else {
            screen = .landing
        }
    }

    func navigate(to screen: AppScreen) {
        withAnimation(.easeInOut(duration: 0.3)) {
            self.screen = screen
            self.error = nil
        }
    }

    // MARK: - SPV Client Management

    func startSPV() {
        guard let address = walletData?.address else { return }

        // Load saved manual peers
        let savedPeers = UserDefaults.standard.stringArray(forKey: "manual_peers") ?? []
        for peerStr in savedPeers {
            let parts = peerStr.split(separator: ":")
            let host = String(parts[0])
            let port = parts.count > 1 ? UInt16(parts[1]) ?? P2PConfig.port : P2PConfig.port
            spvClient.addManualPeer(host: host, port: port)
        }

        Task {
            await spvClient.start(watchAddresses: [address])
        }

        startBalanceRefresh()
    }

    func stopSPV() {
        spvClient.stop()
        stopBalanceRefresh()
    }

    /// Add peers from addnode format (supports pasting multiple lines)
    /// Formats supported:
    /// - addnode=103.13.114.93
    /// - addnode=103.13.114.93:9999
    /// - 103.13.114.93
    /// - 103.13.114.93:9999
    func addPeersFromText(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        var savedPeers = UserDefaults.standard.stringArray(forKey: "manual_peers") ?? []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Strip "addnode=" prefix if present
            var peerStr = trimmed
            if let range = peerStr.range(of: "addnode=", options: .caseInsensitive) {
                peerStr = String(peerStr[range.upperBound...])
            }

            peerStr = peerStr.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !peerStr.isEmpty else { continue }

            // Parse host:port
            let parts = peerStr.split(separator: ":")
            let host = String(parts[0])
            let port = parts.count > 1 ? UInt16(parts[1]) ?? P2PConfig.port : P2PConfig.port

            // Validate IP format (basic check)
            let ipParts = host.split(separator: ".")
            guard ipParts.count == 4, ipParts.allSatisfy({ UInt8($0) != nil }) else { continue }

            spvClient.addManualPeer(host: host, port: port)

            // Save for persistence
            let peerKey = "\(host):\(port)"
            if !savedPeers.contains(peerKey) {
                savedPeers.append(peerKey)
            }
        }

        UserDefaults.standard.set(savedPeers, forKey: "manual_peers")
    }

    // MARK: - Create Wallet

    func createWallet(password: String) {
        loading = true
        error = nil

        Task { @MainActor in
            do {
                let result = try WalletService.createWallet(password: password)
                try WalletService.saveWallet(result.walletData)
                walletData = result.walletData
                mnemonic = result.mnemonic
                privateKey = result.privateKey
                loading = false
                navigate(to: .backup)
            } catch {
                self.error = error.localizedDescription
                loading = false
            }
        }
    }

    // MARK: - Import Wallet

    func importWallet(mnemonic: String, password: String) {
        loading = true
        error = nil

        Task { @MainActor in
            do {
                let result = try WalletService.importWallet(mnemonic: mnemonic, password: password)
                try WalletService.saveWallet(result.walletData)
                walletData = result.walletData
                privateKey = result.privateKey
                self.mnemonic = nil
                loading = false
                navigate(to: .dashboard)
                startSPV()
            } catch {
                self.error = error.localizedDescription
                loading = false
            }
        }
    }

    // MARK: - Unlock

    func unlock(password: String) {
        guard let walletData else { return }
        loading = true
        error = nil

        Task { @MainActor in
            do {
                let result = try WalletService.unlockWallet(walletData: walletData, password: password)
                privateKey = result.privateKey
                loading = false
                navigate(to: .dashboard)
                startSPV()
            } catch {
                self.error = error.localizedDescription
                loading = false
            }
        }
    }

    // MARK: - Logout / Delete

    func logout() {
        stopSPV()
        WalletService.deleteWallet()
        walletData = nil
        privateKey = nil
        mnemonic = nil
        balance = nil
        error = nil
        loading = false
        navigate(to: .landing)
    }

    // MARK: - Balance (from SPV)

    func refreshBalance() {
        guard let address = walletData?.address else { return }

        Task { @MainActor in
            let bal = await SPVWalletService.fetchBalance(address: address)
            self.balance = bal
        }
    }

    func startBalanceRefresh() {
        refreshBalance()
        stopBalanceRefresh()
        balanceTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refreshBalance()
        }
    }

    func stopBalanceRefresh() {
        balanceTimer?.invalidate()
        balanceTimer = nil
    }

    // MARK: - Send Transaction (via SPV P2P)

    func sendTransaction(toAddress: String, amount: String) async throws -> (txid: String, fee: Int) {
        guard let address = walletData?.address, let privateKey else {
            throw WalletError.transactionFailed("Wallet not unlocked")
        }

        guard let amountDuffs = SmartiecoinNetwork.displayToDuffs(amount) else {
            throw WalletError.transactionFailed("Invalid amount")
        }

        let result = try await SPVWalletService.sendTransaction(
            fromAddress: address,
            toAddress: toAddress,
            amountDuffs: amountDuffs,
            privateKey: privateKey
        )

        refreshBalance()
        return result
    }
}
