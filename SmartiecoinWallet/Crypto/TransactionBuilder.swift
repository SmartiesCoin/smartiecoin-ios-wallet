import Foundation
import CryptoKit
import secp256k1

struct UTXO {
    let txid: String
    let outputIndex: Int
    let satoshis: Int
    let script: String
}

enum TransactionBuilder {

    enum TransactionError: Error {
        case insufficientFunds
        case invalidAddress
        case invalidUTXO
        case belowDustThreshold
        case signingFailed
        case invalidPrivateKey
        case noUTXOs
    }

    private static let dustThreshold = 546
    private static let sighashAll: UInt32 = 0x00000001

    // MARK: - Internal Transaction Representation

    private struct TxInput {
        let prevTxid: Data   // 32 bytes, internal byte order (reversed from hex)
        let prevIndex: UInt32
        var scriptSig: Data
        let sequence: UInt32
    }

    private struct TxOutput {
        let value: UInt64
        let scriptPubKey: Data
    }

    private struct RawTransaction {
        let version: UInt32
        var inputs: [TxInput]
        var outputs: [TxOutput]
        let locktime: UInt32
    }

    // MARK: - Public Interface

    /// Builds and signs a P2PKH transaction for Smartiecoin.
    /// - Parameters:
    ///   - fromAddress: The sender's address (used to construct the previous scriptPubKey for signing).
    ///   - toAddress: The recipient's address.
    ///   - amountDuffs: The amount to send in duffs (1 SMART = 100,000,000 duffs).
    ///   - privateKey: The 32-byte private key for signing inputs.
    ///   - utxos: The set of unspent transaction outputs available for spending.
    ///   - feeRate: Fee rate in duffs per byte (default from SmartiecoinNetwork.defaultFeeRate).
    /// - Returns: A tuple of the signed transaction hex, the fee paid, and the transaction ID.
    static func buildTransaction(
        fromAddress: String,
        toAddress: String,
        amountDuffs: Int,
        privateKey: Data,
        utxos: [UTXO],
        feeRate: Int = SmartiecoinNetwork.defaultFeeRate
    ) throws -> (hex: String, fee: Int, txid: String) {
        guard !utxos.isEmpty else {
            throw TransactionError.noUTXOs
        }

        guard amountDuffs > dustThreshold else {
            throw TransactionError.belowDustThreshold
        }

        guard let toPubKeyHash = AddressGenerator.pubKeyHashFromAddress(toAddress) else {
            throw TransactionError.invalidAddress
        }

        guard let fromPubKeyHash = AddressGenerator.pubKeyHashFromAddress(fromAddress) else {
            throw TransactionError.invalidAddress
        }

        // Sort UTXOs largest-first for efficient coin selection
        let sortedUTXOs = utxos.sorted { $0.satoshis > $1.satoshis }

        // Select UTXOs until we have enough to cover amount + estimated fee
        var selectedUTXOs: [UTXO] = []
        var totalInput = 0

        for utxo in sortedUTXOs {
            selectedUTXOs.append(utxo)
            totalInput += utxo.satoshis

            let outputCount = 2 // recipient + potential change
            let estimatedFee = estimateFee(
                inputCount: selectedUTXOs.count,
                outputCount: outputCount,
                feeRate: feeRate
            )

            if totalInput >= amountDuffs + estimatedFee {
                break
            }
        }

        // Determine final fee and change
        let outputCount: Int
        let estimatedFee = estimateFee(
            inputCount: selectedUTXOs.count,
            outputCount: 2,
            feeRate: feeRate
        )

        guard totalInput >= amountDuffs + estimatedFee else {
            throw TransactionError.insufficientFunds
        }

        let change = totalInput - amountDuffs - estimatedFee
        let fee: Int

        // If change is below dust, absorb it into the fee
        if change > 0 && change < dustThreshold {
            fee = estimatedFee + change
            outputCount = 1
        } else if change == 0 {
            fee = estimatedFee
            outputCount = 1
        } else {
            // Recalculate fee with correct output count
            fee = estimatedFee
            outputCount = 2
        }

        // Build outputs
        var outputs: [TxOutput] = []

        let toScriptPubKey = AddressGenerator.scriptPubKeyForP2PKH(pubKeyHash: toPubKeyHash)
        outputs.append(TxOutput(value: UInt64(amountDuffs), scriptPubKey: toScriptPubKey))

        if outputCount == 2 {
            let changeScriptPubKey = AddressGenerator.scriptPubKeyForP2PKH(pubKeyHash: fromPubKeyHash)
            let changeAmount = totalInput - amountDuffs - fee
            outputs.append(TxOutput(value: UInt64(changeAmount), scriptPubKey: changeScriptPubKey))
        }

        // Build inputs (with empty scriptSigs initially)
        var inputs: [TxInput] = []
        for utxo in selectedUTXOs {
            guard let prevTxid = reversedTxidData(utxo.txid) else {
                throw TransactionError.invalidUTXO
            }
            inputs.append(TxInput(
                prevTxid: prevTxid,
                prevIndex: UInt32(utxo.outputIndex),
                scriptSig: Data(),
                sequence: 0xFFFFFFFF
            ))
        }

        var tx = RawTransaction(
            version: 2,
            inputs: inputs,
            outputs: outputs,
            locktime: 0
        )

        // Construct the previous output's scriptPubKey for signing
        let prevScriptPubKey = AddressGenerator.scriptPubKeyForP2PKH(pubKeyHash: fromPubKeyHash)

        // Get the compressed public key from the private key
        let compressedPubKey = try BIP32.publicKeyFromPrivateKey(privateKey)

        // Sign each input
        for i in 0..<tx.inputs.count {
            let preimage = serializeForSigning(tx: tx, inputIndex: i, prevScriptPubKey: prevScriptPubKey)

            // Bitcoin double-SHA256 signing:
            // signature(for: Data) internally does SHA256, so pass SHA256(preimage)
            // to get signature over SHA256(SHA256(preimage)) = double-SHA256
            let firstHash = Data(SHA256.hash(data: preimage))

            let privKey = try secp256k1.Signing.PrivateKey(rawRepresentation: privateKey)
            let sig = try privKey.ecdsa.signature(for: firstHash)
            let derSig = try sig.derRepresentation

            // Build scriptSig: <sig_len> <der_sig> <sighash_type> <pubkey_len> <compressed_pubkey>
            var scriptSig = Data()
            scriptSig.append(UInt8(derSig.count + 1))  // DER signature length + 1 for sighash byte
            scriptSig.append(derSig)
            scriptSig.append(0x01)                       // SIGHASH_ALL
            scriptSig.append(UInt8(compressedPubKey.count))
            scriptSig.append(compressedPubKey)

            tx.inputs[i].scriptSig = scriptSig
        }

        // Serialize the final signed transaction
        let serialized = serializeTransaction(tx)
        let hex = serialized.map { String(format: "%02x", $0) }.joined()

        // TXID is the reversed double SHA256 of the serialized transaction
        let txidData = Base58.doubleSHA256(serialized)
        let txid = Data(txidData.reversed()).map { String(format: "%02x", $0) }.joined()

        return (hex: hex, fee: fee, txid: txid)
    }

    // MARK: - Fee Estimation

    private static func estimateFee(inputCount: Int, outputCount: Int, feeRate: Int) -> Int {
        let estimatedSize = inputCount * 148 + outputCount * 34 + 10
        return estimatedSize * feeRate
    }

    // MARK: - Serialization

    /// Serializes the transaction for signing a specific input (SIGHASH_ALL).
    /// All scriptSigs are emptied except for the input being signed, which receives the
    /// previous output's scriptPubKey. SIGHASH_ALL is appended as 4 bytes LE.
    private static func serializeForSigning(
        tx: RawTransaction,
        inputIndex: Int,
        prevScriptPubKey: Data
    ) -> Data {
        var data = Data()

        // Version (4 bytes LE)
        appendUInt32LE(&data, tx.version)

        // Input count
        data.append(writeVarInt(tx.inputs.count))

        // Inputs
        for (i, input) in tx.inputs.enumerated() {
            data.append(input.prevTxid)                  // 32 bytes prev txid
            appendUInt32LE(&data, input.prevIndex)       // 4 bytes prev index LE

            if i == inputIndex {
                // Current input gets the previous scriptPubKey
                data.append(writeVarInt(prevScriptPubKey.count))
                data.append(prevScriptPubKey)
            } else {
                // All other inputs get empty scriptSig
                data.append(writeVarInt(0))
            }

            appendUInt32LE(&data, input.sequence)        // 4 bytes sequence LE
        }

        // Output count
        data.append(writeVarInt(tx.outputs.count))

        // Outputs
        for output in tx.outputs {
            appendUInt64LE(&data, output.value)          // 8 bytes value LE
            data.append(writeVarInt(output.scriptPubKey.count))
            data.append(output.scriptPubKey)
        }

        // Locktime (4 bytes LE)
        appendUInt32LE(&data, tx.locktime)

        // SIGHASH_ALL (4 bytes LE)
        appendUInt32LE(&data, sighashAll)

        return data
    }

    /// Serializes the fully signed transaction for broadcast.
    private static func serializeTransaction(_ tx: RawTransaction) -> Data {
        var data = Data()

        // Version (4 bytes LE)
        appendUInt32LE(&data, tx.version)

        // Input count
        data.append(writeVarInt(tx.inputs.count))

        // Inputs
        for input in tx.inputs {
            data.append(input.prevTxid)                  // 32 bytes prev txid
            appendUInt32LE(&data, input.prevIndex)       // 4 bytes prev index LE
            data.append(writeVarInt(input.scriptSig.count))
            data.append(input.scriptSig)
            appendUInt32LE(&data, input.sequence)        // 4 bytes sequence LE
        }

        // Output count
        data.append(writeVarInt(tx.outputs.count))

        // Outputs
        for output in tx.outputs {
            appendUInt64LE(&data, output.value)          // 8 bytes value LE
            data.append(writeVarInt(output.scriptPubKey.count))
            data.append(output.scriptPubKey)
        }

        // Locktime (4 bytes LE)
        appendUInt32LE(&data, tx.locktime)

        return data
    }

    // MARK: - Helpers

    /// Encodes an integer as a Bitcoin-style variable-length integer.
    private static func writeVarInt(_ value: Int) -> Data {
        var data = Data()
        if value < 0xFD {
            data.append(UInt8(value))
        } else if value <= 0xFFFF {
            data.append(0xFD)
            var val = UInt16(value).littleEndian
            data.append(Data(bytes: &val, count: 2))
        } else if value <= 0xFFFFFFFF {
            data.append(0xFE)
            var val = UInt32(value).littleEndian
            data.append(Data(bytes: &val, count: 4))
        } else {
            data.append(0xFF)
            var val = UInt64(value).littleEndian
            data.append(Data(bytes: &val, count: 8))
        }
        return data
    }

    /// Converts a hex txid string to 32 bytes in reversed (internal) byte order.
    private static func reversedTxidData(_ txid: String) -> Data? {
        guard txid.count == 64 else { return nil }

        var bytes = Data()
        var index = txid.startIndex
        for _ in 0..<32 {
            let nextIndex = txid.index(index, offsetBy: 2)
            guard let byte = UInt8(txid[index..<nextIndex], radix: 16) else { return nil }
            bytes.append(byte)
            index = nextIndex
        }

        return Data(bytes.reversed())
    }

    private static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        var val = value.littleEndian
        data.append(Data(bytes: &val, count: 4))
    }

    private static func appendUInt64LE(_ data: inout Data, _ value: UInt64) {
        var val = value.littleEndian
        data.append(Data(bytes: &val, count: 8))
    }
}
