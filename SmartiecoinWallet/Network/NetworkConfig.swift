import Foundation

enum SmartiecoinNetwork {
    // Address prefixes (from src/chainparams.cpp base58Prefixes)
    static let pubKeyHash: UInt8 = 0x3F      // 63 - addresses start with 'S'
    static let scriptHash: UInt8 = 0x52      // 82 - addresses start with 'R'
    static let wif: UInt8 = 0x80             // 128

    // BIP32 keys
    static let bip32Public: UInt32 = 0x0488B21E
    static let bip32Private: UInt32 = 0x0488ADE4

    // BIP44 coin type - kept at 5001 for compatibility with existing wallets
    // Note: chainparams.cpp nExtCoinType = 5, but the web/mobile wallet uses 5001
    static let coinType: UInt32 = 5001
    static let derivationPath = "m/44'/5001'/0'/0/0"

    // Units: 1 SMT = 100,000,000 duffs
    static let coin: Int = 100_000_000
    static let defaultFeeRate = 10
    static let dustThreshold = 546

    // P2P network (from src/chainparams.cpp)
    static let p2pPort: UInt16 = 8383
    static let blockTime: Int = 60  // 1-minute blocks

    // Legacy API base (kept for fallback, SPV is primary)
    static let apiBase = "https://wallet.smartiecoin.com/api"

    // Message signing prefix
    static let messagePrefix = "\u{19}Smartiecoin Signed Message:\n"
    static let bech32Hrp = "smt"

    static func smtToDisplay(_ duffs: Int) -> String {
        let value = Double(duffs) / Double(coin)
        return String(format: "%.8f", value)
    }

    static func displayToDuffs(_ smt: String) -> Int? {
        guard let value = Double(smt), value >= 0 else { return nil }
        return Int(round(value * Double(coin)))
    }
}
