import Foundation

enum WalletService {
    static func createWallet(password: String) throws -> (walletData: WalletData, mnemonic: String, privateKey: Data) {
        let mnemonic = BIP39.generateMnemonic()
        let (walletData, privateKey) = try deriveAndEncrypt(mnemonic: mnemonic, password: password)
        return (walletData, mnemonic, privateKey)
    }

    static func importWallet(mnemonic: String, password: String) throws -> (walletData: WalletData, privateKey: Data) {
        let cleaned = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard BIP39.validateMnemonic(cleaned) else {
            throw WalletError.invalidMnemonic
        }
        return try deriveAndEncrypt(mnemonic: cleaned, password: password)
    }

    static func unlockWallet(walletData: WalletData, password: String) throws -> (privateKey: Data, mnemonic: String) {
        let mnemonic = try WalletEncryption.decrypt(encryptedHex: walletData.encryptedMnemonic, password: password)
        let privKeyHex = try WalletEncryption.decrypt(encryptedHex: walletData.encryptedPrivKey, password: password)
        guard let privateKey = Data(hexString: privKeyHex) else {
            throw WalletError.decryptionFailed
        }
        return (privateKey, mnemonic)
    }

    static func saveWallet(_ walletData: WalletData) throws {
        try KeychainService.save(walletData: walletData)
    }

    static func loadWallet() -> WalletData? {
        KeychainService.load()
    }

    static func deleteWallet() {
        KeychainService.delete()
    }

    static func sendTransaction(
        fromAddress: String,
        toAddress: String,
        amountDuffs: Int,
        privateKey: Data
    ) async throws -> (txid: String, fee: Int) {
        let utxos = try await APIService.fetchUTXOs(address: fromAddress)
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

        let txid = try await APIService.broadcastTransaction(hex: result.hex)
        return (txid, result.fee)
    }

    private static func deriveAndEncrypt(mnemonic: String, password: String) throws -> (WalletData, Data) {
        let seed = BIP39.mnemonicToSeed(mnemonic: mnemonic)
        let derived: (privateKey: Data, chainCode: Data)
        do {
            derived = try BIP32.deriveKeyFromPath(seed: seed, path: SmartiecoinNetwork.derivationPath)
        } catch {
            throw WalletError.keyDerivationFailed
        }

        let publicKey = try BIP32.publicKeyFromPrivateKey(derived.privateKey)
        let address = AddressGenerator.p2pkhAddress(publicKey: publicKey)

        let encryptedMnemonic = try WalletEncryption.encrypt(plaintext: mnemonic, password: password)
        let encryptedPrivKey = try WalletEncryption.encrypt(plaintext: derived.privateKey.hexString, password: password)

        let walletData = WalletData(
            address: address,
            encryptedMnemonic: encryptedMnemonic,
            encryptedPrivKey: encryptedPrivKey
        )

        return (walletData, derived.privateKey)
    }
}
