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
        #if WALLET_MODE_API
        startBalanceRefresh()
        return
        #else
        guard let address = walletData?.address else {
            startBalanceRefresh()
            return
        }

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
        #endif
    }

    func stopSPV() {
        spvClient.stop()
        stopBalanceRefresh()
    }

    func addPeersFromText(_ text: String) {
        let lines = text.components(separatedBy: CharacterSet.newlines.union(.init(charactersIn: ";")))
        var savedPeers = UserDefaults.standard.stringArray(forKey: "manual_peers") ?? []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            var peerStr = trimmed
            if let range = peerStr.range(of: "addnode=", options: .caseInsensitive) {
                peerStr = String(peerStr[range.upperBound...])
            }

            peerStr = peerStr.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !peerStr.isEmpty else { continue }

            let parts = peerStr.split(separator: ":")
            let host = String(parts[0])
            let port = parts.count > 1 ? UInt16(parts[1]) ?? P2PConfig.port : P2PConfig.port

            // Validate - allow IPs and hostnames
            guard host.count >= 4 else { continue }

            spvClient.addManualPeer(host: host, port: port)

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

        let pw = password
        Task {
            do {
                let result = try await runInBackground {
                    try WalletService.createWallet(password: pw)
                }
                try WalletService.saveWallet(result.walletData)
                await MainActor.run {
                    self.walletData = result.walletData
                    self.mnemonic = result.mnemonic
                    self.privateKey = result.privateKey
                    self.loading = false
                    self.navigate(to: .backup)
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.loading = false
                }
            }
        }
    }

    // MARK: - Import Wallet

    func importWallet(mnemonic: String, password: String) {
        loading = true
        error = nil

        let mn = mnemonic
        let pw = password
        Task {
            do {
                let result = try await runInBackground {
                    try WalletService.importWallet(mnemonic: mn, password: pw)
                }
                try WalletService.saveWallet(result.walletData)
                await MainActor.run {
                    self.walletData = result.walletData
                    self.privateKey = result.privateKey
                    self.mnemonic = nil
                    self.loading = false
                    self.navigate(to: .dashboard)
                    self.startSPV()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.loading = false
                }
            }
        }
    }

    // MARK: - Unlock

    func unlock(password: String) {
        guard let wd = walletData else { return }
        loading = true
        error = nil

        let pw = password
        Task {
            do {
                let result = try await runInBackground {
                    try WalletService.unlockWallet(walletData: wd, password: pw)
                }
                await MainActor.run {
                    self.privateKey = result.privateKey
                    self.loading = false
                    self.navigate(to: .dashboard)
                    self.startSPV()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.loading = false
                }
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

    // MARK: - Balance

    func refreshBalance() {
        guard let address = walletData?.address else { return }

        Task {
            #if WALLET_MODE_API
            do {
                let bal = try await APIService.fetchBalance(address: address)
                await MainActor.run { self.balance = bal }
            } catch {}
            #else
            let bal = await SPVWalletService.fetchBalance(address: address)
            await MainActor.run { self.balance = bal }
            #endif
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

    // MARK: - Send Transaction

    func sendTransaction(toAddress: String, amount: String) async throws -> (txid: String, fee: Int) {
        guard let address = walletData?.address, let privateKey else {
            throw WalletError.transactionFailed("Wallet not unlocked")
        }

        guard let amountDuffs = SmartiecoinNetwork.displayToDuffs(amount) else {
            throw WalletError.transactionFailed("Invalid amount")
        }

        #if WALLET_MODE_API
        let result = try await WalletService.sendTransaction(
            fromAddress: address,
            toAddress: toAddress,
            amountDuffs: amountDuffs,
            privateKey: privateKey
        )
        #else
        let result = try await SPVWalletService.sendTransaction(
            fromAddress: address,
            toAddress: toAddress,
            amountDuffs: amountDuffs,
            privateKey: privateKey
        )
        #endif

        refreshBalance()
        return result
    }

    // MARK: - Background Work Helper

    private func runInBackground<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
