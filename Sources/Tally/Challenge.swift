#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Crypto

public struct Challenge: Sendable {
    public let nonce: Data
    public let boundPeer: PeerID
    public let difficulty: Int
    public let issuedAt: ContinuousClock.Instant
    public let expiresAfter: Duration

    public init(boundPeer: PeerID, difficulty: Int = 16, expiresAfter: Duration = .seconds(30)) {
        precondition((0...256).contains(difficulty), "difficulty must be between 0 and 256")
        precondition(expiresAfter > .zero, "expiresAfter must be positive")

        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<bytes.count {
            bytes[i] = UInt8.random(in: 0...255)
        }
        self.nonce = Data(bytes)
        self.boundPeer = boundPeer
        self.difficulty = difficulty
        self.issuedAt = .now
        self.expiresAfter = expiresAfter
    }

    init(
        nonce: Data,
        boundPeer: PeerID,
        difficulty: Int,
        issuedAt: ContinuousClock.Instant = .now,
        expiresAfter: Duration = .seconds(30)
    ) {
        precondition((0...256).contains(difficulty), "difficulty must be between 0 and 256")
        precondition(expiresAfter > .zero, "expiresAfter must be positive")

        self.nonce = nonce
        self.boundPeer = boundPeer
        self.difficulty = difficulty
        self.issuedAt = issuedAt
        self.expiresAfter = expiresAfter
    }

    public var isExpired: Bool {
        issuedAt.duration(to: .now) >= expiresAfter
    }

    public func verify(solution: Data, peer: PeerID) -> Bool {
        verify(solution: solution, peer: peer, at: .now)
    }

    func verify(solution: Data, peer: PeerID, at now: ContinuousClock.Instant) -> Bool {
        guard boundPeer == peer else { return false }
        guard !isExpired(at: now) else { return false }
        return meetsTarget(solution: solution)
    }

    func meetsTarget(solution: Data) -> Bool {
        var input = nonce
        input.append(Data(boundPeer.publicKey.utf8))
        input.append(solution)
        let hash = SHA256.hash(data: input)
        return leadingZeroBits(hash) >= difficulty
    }

    func isExpired(at now: ContinuousClock.Instant) -> Bool {
        issuedAt.duration(to: now) >= expiresAfter
    }

    private func leadingZeroBits(_ hash: SHA256.Digest) -> Int {
        var bits = 0
        for byte in hash {
            if byte == 0 {
                bits += 8
            } else {
                bits += byte.leadingZeroBitCount
                break
            }
        }
        return bits
    }
}

public struct ChallengeSolver: Sendable {
    public init() {}

    public func solve(_ challenge: Challenge) -> Data? {
        var counter: UInt64 = 0
        while !challenge.isExpired {
            let solution = withUnsafeBytes(of: &counter) { Data($0) }
            if challenge.meetsTarget(solution: solution) {
                return solution
            }
            guard counter < .max else { return nil }
            counter += 1
        }
        return nil
    }
}
