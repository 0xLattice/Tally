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

public struct CreditLine: Sendable {
    public let peerA: PeerID
    public let peerB: PeerID
    public private(set) var balance: Int64
    public private(set) var sequence: UInt64
    public private(set) var threshold: UInt64
    public private(set) var successfulSettlements: UInt64

    public init(peerA: PeerID, peerB: PeerID, threshold: UInt64) {
        self.peerA = peerA
        self.peerB = peerB
        self.balance = 0
        self.sequence = 0
        self.threshold = threshold
        self.successfulSettlements = 0
    }

    public static func initialThreshold(baseTrust: Double, multiplier: UInt64 = 100) -> UInt64 {
        guard baseTrust.isFinite, baseTrust > 0 else { return 0 }
        guard baseTrust < 1 else { return multiplier }
        let scaled = baseTrust * Double(multiplier)
        return scaled >= Double(UInt64.max) ? .max : UInt64(scaled)
    }

    public var needsSettlement: Bool {
        clampedBalanceMagnitude >= clampedThreshold
    }

    public var availableCapacity: Int64 {
        clampedThreshold - clampedBalanceMagnitude
    }

    /// Continuous debt pressure from 0.0 (no debt) to 1.0 (at or past threshold).
    /// Use for graduated throttling: higher pressure means less bandwidth.
    public var debtPressure: Double {
        let threshold = clampedThreshold
        guard threshold > 0 else { return 1.0 }
        return min(Double(clampedBalanceMagnitude) / Double(threshold), 1.0)
    }

    private var clampedThreshold: Int64 {
        Int64(min(threshold, UInt64(Int64.max)))
    }

    private var clampedBalanceMagnitude: Int64 {
        Int64(min(balance.magnitude, UInt64(Int64.max)))
    }

    public mutating func adjustBalance(by amount: Int64) {
        let (updated, overflow) = balance.addingReportingOverflow(amount)
        balance = overflow ? (amount >= 0 ? .max : .min) : updated
        Self.increment(&sequence)
    }

    public mutating func recordSettlement() {
        balance = 0
        Self.increment(&successfulSettlements)
        let currentScale = Self.settlementScale(successfulSettlements)
        let nextScale = Self.settlementScale(successfulSettlements == .max ? .max : successfulSettlements + 1)
        let roundedInitial = threshold / currentScale
            + (threshold.isMultiple(of: currentScale) ? 0 : 1)
        let initial = max(roundedInitial, 1)
        let (updated, overflow) = initial.multipliedReportingOverflow(by: nextScale)
        threshold = overflow ? .max : updated
    }

    public mutating func recordPartialSettlement(workValue: Int64) {
        guard workValue > 0 else { return }
        if balance > 0 {
            balance = max(0, balance - workValue)
        } else {
            balance = min(0, balance + workValue)
        }
        Self.increment(&sequence)
    }

    public mutating func recordMissedSettlement() {
        threshold = threshold / 2
    }

    private static func settlementScale(_ count: UInt64) -> UInt64 {
        UInt64(1 + log2(Double(count)))
    }

    private static func increment(_ value: inout UInt64) {
        if value < .max { value += 1 }
    }
}
