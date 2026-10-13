#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
// The C math functions, which Foundation would otherwise re-export.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Decayed bytes of content the host requested from a peer and verified.
/// Kept apart from admission evidence: it is fed only by verified,
/// solicited content, and it is bounded and evicted on its own, so credit
/// cannot change which peers' admission evidence survives.
struct UsefulCredit: Sendable {
    private(set) var bytes: Double = 0
    private(set) var lastUpdate: ContinuousClock.Instant

    init(now: ContinuousClock.Instant) {
        self.lastUpdate = now
    }

    mutating func record(_ added: Int, at now: ContinuousClock.Instant, halfLife: Double) {
        bytes = value(at: now, halfLife: halfLife) + Double(added)
        lastUpdate = max(lastUpdate, now)
    }

    /// The credit decayed to `now`, without changing the record.
    func value(at now: ContinuousClock.Instant, halfLife: Double) -> Double {
        let elapsed = lastUpdate.duration(to: now)
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        guard seconds > 0 else { return bytes }
        return bytes * exp2(-seconds / halfLife)
    }
}
