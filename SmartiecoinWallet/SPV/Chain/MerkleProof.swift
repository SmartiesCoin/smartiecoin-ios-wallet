import Foundation

/// Verifies Merkle proofs from merkleblock messages (BIP37)
enum MerkleProof {

    /// Extract matched transaction hashes from a merkleblock message
    /// Returns the transaction hashes that matched our bloom filter
    static func extractMatches(from merkleBlock: MerkleBlockMessage) -> [Data]? {
        let totalTransactions = Int(merkleBlock.totalTransactions)
        guard totalTransactions > 0 else { return nil }

        var matchedHashes = [Data]()
        var hashIndex = 0
        var flagBitIndex = 0

        let calculatedRoot = traverseAndExtract(
            hashes: merkleBlock.hashes,
            flags: merkleBlock.flags,
            totalLeaves: totalTransactions,
            height: treeHeight(totalTransactions),
            position: 0,
            hashIndex: &hashIndex,
            flagBitIndex: &flagBitIndex,
            matchedHashes: &matchedHashes
        )

        // Verify the calculated Merkle root matches the header's Merkle root
        guard let root = calculatedRoot, root == merkleBlock.header.merkleRoot else {
            return nil
        }

        // Verify all hashes and flags were consumed
        guard hashIndex == merkleBlock.hashes.count else { return nil }

        return matchedHashes
    }

    /// Verify that a transaction hash is included in a block with the given Merkle root
    static func verify(txHash: Data, merkleBlock: MerkleBlockMessage) -> Bool {
        guard let matches = extractMatches(from: merkleBlock) else { return false }
        return matches.contains(txHash)
    }

    // MARK: - Private

    private static func treeHeight(_ leafCount: Int) -> Int {
        var height = 0
        var size = leafCount
        while size > 1 {
            height += 1
            size = (size + 1) / 2
        }
        return height
    }

    private static func treeWidth(at height: Int, totalLeaves: Int, treeHeight: Int) -> Int {
        let levelFromBottom = treeHeight - height
        var width = totalLeaves
        for _ in 0..<levelFromBottom {
            width = (width + 1) / 2
        }
        return width
    }

    private static func traverseAndExtract(
        hashes: [Data],
        flags: Data,
        totalLeaves: Int,
        height: Int,
        position: Int,
        hashIndex: inout Int,
        flagBitIndex: inout Int,
        matchedHashes: inout [Data]
    ) -> Data? {
        // Read flag bit
        guard flagBitIndex / 8 < flags.count else { return nil }
        let flag = (flags[flagBitIndex / 8] >> (flagBitIndex % 8)) & 1
        flagBitIndex += 1

        if height == 0 || flag == 0 {
            // Leaf node or pruned subtree - consume a hash
            guard hashIndex < hashes.count else { return nil }
            let hash = hashes[hashIndex]
            hashIndex += 1

            if height == 0 && flag == 1 {
                // This is a matched transaction
                matchedHashes.append(hash)
            }

            return hash
        }

        // Internal node with flag=1: descend
        let left = traverseAndExtract(
            hashes: hashes, flags: flags, totalLeaves: totalLeaves,
            height: height - 1, position: position * 2,
            hashIndex: &hashIndex, flagBitIndex: &flagBitIndex,
            matchedHashes: &matchedHashes
        )

        let right: Data?
        let rightPosition = position * 2 + 1
        let width = Self.treeWidth(at: height - 1, totalLeaves: totalLeaves, treeHeight: height)

        if rightPosition < width {
            right = traverseAndExtract(
                hashes: hashes, flags: flags, totalLeaves: totalLeaves,
                height: height - 1, position: rightPosition,
                hashIndex: &hashIndex, flagBitIndex: &flagBitIndex,
                matchedHashes: &matchedHashes
            )
        } else {
            right = left  // Duplicate left if no right child
        }

        guard let l = left, let r = right else { return nil }

        // Compute parent hash = double SHA256(left || right)
        var combined = Data()
        combined.append(l)
        combined.append(r)
        return Base58.doubleSHA256(combined)
    }
}
