import Foundation
import Testing
@testable import Tally

@Suite("Serving balance")
struct ServingBalanceTests {
    @Test("credits accumulate and spending clamps at zero")
    func creditAndSpend() {
        let tally = Tally()
        let peer = PeerID(publicKey: "payer")
        tally.creditServingBalance(peer: peer, bytes: 1_000)
        tally.creditServingBalance(peer: peer, bytes: 500)
        #expect(tally.servingBalance(for: peer) == 1_500)
        tally.spendServingBalance(peer: peer, bytes: 400)
        #expect(tally.servingBalance(for: peer) == 1_100)
        tally.spendServingBalance(peer: peer, bytes: 5_000)
        #expect(tally.servingBalance(for: peer) == 0)
        #expect(tally.servingBalances().isEmpty)
        tally.spendServingBalance(peer: PeerID(publicKey: "stranger"), bytes: 10)
        #expect(tally.servingBalance(for: PeerID(publicKey: "stranger")) == 0)
    }

    @Test("zero and negative amounts are ignored")
    func nonPositiveIgnored() {
        let tally = Tally()
        let peer = PeerID(publicKey: "payer")
        tally.creditServingBalance(peer: peer, bytes: 0)
        tally.creditServingBalance(peer: peer, bytes: -5)
        #expect(tally.servingBalance(for: peer) == 0)
        tally.creditServingBalance(peer: peer, bytes: 100)
        tally.spendServingBalance(peer: peer, bytes: -5)
        #expect(tally.servingBalance(for: peer) == 100)
    }

    @Test("credit saturates instead of overflowing")
    func creditSaturates() {
        let tally = Tally()
        let peer = PeerID(publicKey: "payer")
        tally.creditServingBalance(peer: peer, bytes: .max)
        tally.creditServingBalance(peer: peer, bytes: 1)
        #expect(tally.servingBalance(for: peer) == .max)
    }

    @Test("the balance does not decay")
    func noDecay() {
        let start = ContinuousClock.now
        var state = Tally.State(config: TallyConfig(decayHalfLife: 1))
        let peer = PeerID(publicKey: "payer")
        state.creditBalance(peer: peer, bytes: 1_000)
        let later = start.advanced(by: .seconds(3_600))
        #expect(state.balance.value(forKey: peer) == 1_000)
        #expect(state.servingPriority(for: peer, at: later, halfLife: 1) == 1_000)
    }

    @Test("priority is useful credit plus balance")
    func priorityIncludesBalance() {
        let start = ContinuousClock.now
        var state = Tally.State(config: TallyConfig(decayHalfLife: 60))
        let peer = PeerID(publicKey: "payer")
        state.recordUseful(peer: peer, bytes: 1_000, at: start, halfLife: 60)
        state.creditBalance(peer: peer, bytes: 500)
        #expect(abs(state.servingPriority(for: peer, at: start, halfLife: 60) - 1_500) < 0.000_001)

        let tally = Tally()
        let payer = PeerID(publicKey: "payer")
        tally.creditServingBalance(peer: payer, bytes: 2_048)
        #expect(tally.servingPriority(for: payer) == 2_048)
    }

    @Test("at capacity, the smallest balance is dropped")
    func evictsSmallest() {
        // Capacity = maxPeers × 4 = 4 balance records.
        let tally = Tally(config: TallyConfig(maxPeers: 1))
        let large = (0..<3).map { PeerID(publicKey: "large-\($0)") }
        let small = PeerID(publicKey: "small")
        tally.creditServingBalance(peer: small, bytes: 10)
        for peer in large { tally.creditServingBalance(peer: peer, bytes: 1_000) }
        for index in 0..<50 {
            tally.creditServingBalance(peer: PeerID(publicKey: "flood-\(index)"), bytes: 1)
        }
        let balances = tally.servingBalances()
        #expect(balances.count == 4)
        #expect(balances[small] == 10)
        for peer in large { #expect(balances[peer] == 1_000) }
    }

    @Test("exported balances restore into a fresh tally")
    func exportRestore() {
        let tally = Tally()
        let first = PeerID(publicKey: "first")
        let second = PeerID(publicKey: "second")
        tally.creditServingBalance(peer: first, bytes: 100)
        tally.creditServingBalance(peer: second, bytes: 200)
        let exported = tally.servingBalances()
        #expect(exported == [first: 100, second: 200])

        let restored = Tally()
        for (peer, bytes) in exported { restored.creditServingBalance(peer: peer, bytes: bytes) }
        #expect(restored.servingBalances() == exported)
        #expect(restored.servingPriority(for: second) == 200)
    }
}
