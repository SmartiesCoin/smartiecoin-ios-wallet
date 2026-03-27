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

@MainActor
final class WalletViewModel: ObservableObject {
    @Published var screen: AppScreen = .loading
    @Published var walletData: WalletData?
    @Published var privateKey: Data?
    @Published var mnemonic: String?
    @Published var balance: BalanceResponse?
    @Published var error: String?
    @Published var loading = false
    @Published var spvClient = SPVClient()

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

    // MARK: - Create Wallet

    func createWallet(password: String) {
        loading = true
        error = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try WalletService.createWallet(password: password)
                try WalletService.saveWallet(result.walletData)

                DispatchQueue.main.async {
                    self.walletData = result.walletData
                    self.mnemonic = result.mnemonic
                    self.privateKey = result.privateKey
                    self.loading = false
                    self.navigate(to: .backup)
                }
            } catch {
                DispatchQueue.main.async {
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

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try WalletService.importWallet(mnemonic: mnemonic, password: password)
                try WalletService.saveWallet(result.walletData)

                DispatchQueue.main.async {
                    self.walletData = result.walletData
                    self.privateKey = result.privateKey
                    self.mnemonic = nil
                    self.loading = false
                    self.navigate(to: .dashboard)
                    self.startSPV()
                }
            } catch {
                DispatchQueue.main.async {
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

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try WalletService.unlockWallet(walletData: wd, password: password)

                DispatchQueue.main.async {
                    self.privateKey = result.privateKey
                    self.loading = false
                    self.navigate(to: .dashboard)
                    self.startSPV()
                }
            } catch {
                DispatchQueue.main.async {
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

    // MARK: - SPV

    func startSPV() {
        startBalanceRefresh()
    }

    func stopSPV() {
        spvClient.stop()
        stopBalanceRefresh()
    }

    var spvStarted = false

    func startSPVIfNeeded() {
        guard !spvStarted else { return }
        guard let address = walletData?.address else { return }
        spvStarted = true

        let savedPeers = UserDefaults.standard.stringArray(forKey: "manual_peers") ?? []
        for peerStr in savedPeers {
            let parts = peerStr.split(separator: ":")
            guard parts.count >= 1 else { continue }
            let host = String(parts[0])
            let port = parts.count > 1 ? UInt16(parts[1]) ?? P2PConfig.port : P2PConfig.port
            spvClient.addManualPeer(host: host, port: port)
        }

        Task {
            await spvClient.start(watchAddresses: [address])
        }
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
            guard peerStr.count >= 4 else { continue }

            let parts = peerStr.split(separator: ":")
            let host = String(parts[0])
            let port = parts.count > 1 ? UInt16(parts[1]) ?? P2PConfig.port : P2PConfig.port

            spvClient.addManualPeer(host: host, port: port)

            let peerKey = "\(host):\(port)"
            if !savedPeers.contains(peerKey) {
                savedPeers.append(peerKey)
            }
        }

        UserDefaults.standard.set(savedPeers, forKey: "manual_peers")
    }

    // MARK: - Balance

    func refreshBalance() {
        guard let address = walletData?.address else { return }

        #if WALLET_MODE_API
        Task {
            do {
                let bal = try await APIService.fetchBalance(address: address)
                self.balance = bal
            } catch {}
        }
        #else
        Task {
            let bal = await SPVWalletService.fetchBalance(address: address)
            self.balance = bal
        }
        #endif
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

    // MARK: - Send

    func sendTransaction(toAddress: String, amount: String) async throws -> (txid: String, fee: Int) {
        guard let address = walletData?.address, let privateKey else {
            throw WalletError.transactionFailed("Wallet not unlocked")
        }
        guard let amountDuffs = SmartiecoinNetwork.displayToDuffs(amount) else {
            throw WalletError.transactionFailed("Invalid amount")
        }

        #if WALLET_MODE_API
        return try await WalletService.sendTransaction(
            fromAddress: address, toAddress: toAddress,
            amountDuffs: amountDuffs, privateKey: privateKey
        )
        #else
        return try await SPVWalletService.sendTransaction(
            fromAddress: address, toAddress: toAddress,
            amountDuffs: amountDuffs, privateKey: privateKey
        )
        #endif
    }
}
