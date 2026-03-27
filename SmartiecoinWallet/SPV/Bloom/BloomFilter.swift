import Foundation

/// BIP37 Bloom Filter for SPV transaction filtering
struct BloomFilter {
    private var filter: [UInt8]
    let nHashFuncs: UInt32
    let nTweak: UInt32

    // Bloom filter update flags
    static let BLOOM_UPDATE_NONE: UInt8 = 0
    static let BLOOM_UPDATE_ALL: UInt8 = 1
    static let BLOOM_UPDATE_P2PUBKEY_ONLY: UInt8 = 2

    /// Create a bloom filter optimized for the expected number of elements
    /// with the given false positive rate
    init(elements: Int, falsePositiveRate: Double = 0.0001) {
        // Calculate optimal filter size (in bytes)
        // filterSize = -1.0 / (ln(2)^2) * nElements * ln(FPrate) / 8
        let ln2 = log(2.0)
        let ln2sq = ln2 * ln2
        let filterBits = -1.0 / ln2sq * Double(elements) * log(falsePositiveRate)
        let filterBytes = min(Int(ceil(filterBits / 8.0)), 36000) // Max 36000 bytes

        self.filter = [UInt8](repeating: 0, count: max(filterBytes, 1))

        // Optimal number of hash functions
        // nHashFuncs = filterSize * 8 / nElements * ln(2)
        let nFuncs = Double(filterBytes * 8) / Double(max(elements, 1)) * ln2
        self.nHashFuncs = min(UInt32(ceil(nFuncs)), 50)  // Max 50

        self.nTweak = UInt32.random(in: 0...UInt32.max)
    }

    /// Insert data into the bloom filter
    mutating func insert(_ data: Data) {
        let filterSize = UInt32(filter.count * 8)
        guard filterSize > 0 else { return }

        for i in 0..<nHashFuncs {
            let hash = murmurHash3(data: data, seed: i &* 0xFBA4C795 &+ nTweak)
            let bit = hash % filterSize
            filter[Int(bit / 8)] |= (1 << (bit % 8))
        }
    }

    /// Insert raw bytes into the bloom filter
    mutating func insert(_ bytes: [UInt8]) {
        insert(Data(bytes))
    }

    /// Check if data might be in the filter (can have false positives)
    func contains(_ data: Data) -> Bool {
        let filterSize = UInt32(filter.count * 8)
        guard filterSize > 0 else { return false }

        for i in 0..<nHashFuncs {
            let hash = murmurHash3(data: data, seed: i &* 0xFBA4C795 &+ nTweak)
            let bit = hash % filterSize
            if filter[Int(bit / 8)] & (1 << (bit % 8)) == 0 {
                return false
            }
        }
        return true
    }

    /// Serialize for filterload message
    func toFilterLoadMessage() -> FilterLoadMessage {
        FilterLoadMessage(
            filter: Data(filter),
            nHashFuncs: nHashFuncs,
            nTweak: nTweak,
            nFlags: Self.BLOOM_UPDATE_ALL
        )
    }

    // MARK: - MurmurHash3 (32-bit)

    private func murmurHash3(data: Data, seed: UInt32) -> UInt32 {
        let c1: UInt32 = 0xCC9E2D51
        let c2: UInt32 = 0x1B873593
        let length = data.count
        var h1 = seed

        // Body - process 4-byte chunks
        let nblocks = length / 4
        for i in 0..<nblocks {
            let offset = i * 4
            var k1 = UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)

            k1 &*= c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 &*= c2

            h1 ^= k1
            h1 = (h1 << 13) | (h1 >> 19)
            h1 = h1 &* 5 &+ 0xE6546B64
        }

        // Tail
        let tail = nblocks * 4
        var k1: UInt32 = 0

        switch length & 3 {
        case 3:
            k1 ^= UInt32(data[tail + 2]) << 16
            fallthrough
        case 2:
            k1 ^= UInt32(data[tail + 1]) << 8
            fallthrough
        case 1:
            k1 ^= UInt32(data[tail])
            k1 &*= c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 &*= c2
            h1 ^= k1
        default:
            break
        }

        // Finalization
        h1 ^= UInt32(length)
        h1 ^= h1 >> 16
        h1 &*= 0x85EBCA6B
        h1 ^= h1 >> 13
        h1 &*= 0xC2B2AE35
        h1 ^= h1 >> 16

        return h1
    }
}
