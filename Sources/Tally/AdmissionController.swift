#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Per-peer token buckets and global send-rate pressure.
struct AdmissionController: Sendable {
    let config: TallyConfig

    var requestBuckets: BoundedMap<PeerID, RequestTokenBucket>
    var windowBytesSent: Int = 0
    var windowStart: ContinuousClock.Instant = .now

    init(config: TallyConfig) {
        self.config = config
        self.requestBuckets = BoundedMap(capacity: config.boundedPeerStateCapacity)
    }

    /// Try to consume one per-peer request token. Returns `true` if a token was
    /// available (and consumed). A brand-new peer starts with a full bucket.
    mutating func consumeRequestToken(peer: PeerID, at now: ContinuousClock.Instant) -> Bool {
        var bucket = requestBuckets.value(forKey: peer) ?? RequestTokenBucket(
            capacity: config.perPeerRequestCapacity,
            refillPerSecond: config.perPeerRequestRefillPerSecond,
            now: now
        )
        let allowed = bucket.tryConsume(at: now)
        requestBuckets.setValue(bucket, forKey: peer)
        return allowed
    }

    mutating func removePeer(_ peer: PeerID) {
        requestBuckets.removeValue(forKey: peer)
    }

    /// Record raw sent bytes into the global rate window.
    mutating func recordSentBytes(_ bytes: Int, at now: ContinuousClock.Instant) {
        let elapsed = windowStart.duration(to: now)
        let elapsedSec = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        if elapsedSec >= config.rateWindow {
            windowBytesSent = bytes
            windowStart = now
        } else {
            windowBytesSent.addSaturating(bytes)
        }
    }

    /// Global rate pressure in `[0, 2]` relative to the configured limit.
    mutating func ratePressure(at now: ContinuousClock.Instant) -> Double {
        let elapsed = windowStart.duration(to: now)
        let elapsedSec = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        if elapsedSec >= config.rateWindow {
            windowBytesSent = 0
            windowStart = now
            return 0
        }
        let windowBudget = config.rateLimitBytesPerSecond * config.rateWindow
        return min(Double(windowBytesSent) / windowBudget, 2.0)
    }

    /// Whether a peer with the given admission score passes the pressure-scaled gate.
    /// Below 0.5 pressure the caller short-circuits to allow; this covers the
    /// `pressure >= 0.5` regime where peer evidence matters.
    func passesPressureGate(admissionScore: Double, pressure: Double) -> Bool {
        let threshold = min(max((pressure - 0.5) * 1.6, 0), 0.8)
        return admissionScore >= threshold
    }
}

struct RequestTokenBucket: Sendable {
    var tokens: Double
    var lastRefill: ContinuousClock.Instant
    let capacity: Double
    let refillPerSecond: Double

    init(capacity: Double, refillPerSecond: Double, now: ContinuousClock.Instant) {
        self.capacity = max(capacity, 1)
        self.refillPerSecond = max(refillPerSecond, 0)
        self.tokens = self.capacity
        self.lastRefill = now
    }

    mutating func tryConsume(at now: ContinuousClock.Instant, cost: Double = 1) -> Bool {
        let elapsed = lastRefill.duration(to: now)
        let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        if elapsedSeconds > 0 {
            tokens = min(capacity, tokens + elapsedSeconds * refillPerSecond)
            lastRefill = now
        }
        guard tokens >= cost else { return false }
        tokens -= cost
        return true
    }
}
