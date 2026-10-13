#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct PeerID: Hashable, Sendable, CustomStringConvertible {
    public let publicKey: String
    public let trailingZeroBits: Int

    public init(publicKey: String) {
        let canonicalKey = KeyDifficulty.canonicalRawHex(publicKey)
        self.publicKey = canonicalKey
        self.trailingZeroBits = KeyDifficulty.trailingZeroBits(of: canonicalKey)
    }

    public var description: String { publicKey }
}
