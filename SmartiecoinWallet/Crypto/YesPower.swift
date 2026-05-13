import Foundation

enum YesPower {
    /// Compute the Smartiecoin block hash (yespower) of an 80-byte block header.
    /// Returns the 32-byte hash in internal byte order.
    static func hash(headerBytes: Data) -> Data {
        var input = [UInt8](repeating: 0, count: 80)
        let count = min(headerBytes.count, 80)
        headerBytes.copyBytes(to: &input, count: count)

        var output = [Int8](repeating: 0, count: 32)
        _ = input.withUnsafeBufferPointer { inputPtr in
            output.withUnsafeMutableBufferPointer { outputPtr in
                inputPtr.baseAddress!.withMemoryRebound(to: Int8.self, capacity: 80) { inputCharPtr in
                    yespower_hash(inputCharPtr, outputPtr.baseAddress!)
                }
            }
        }

        return Data(output.map { UInt8(bitPattern: $0) })
    }
}
