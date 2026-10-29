import Foundation
import Testing
@testable import Tally

@Suite("Standing")
struct StandingTests {
    @Test("a peer with no standing has zero priority and no entry")
    func unknownPeerIsZero() {
        let tally = Tally()
        let stranger = PeerID(publicKey: "stranger")
        #expect(tally.standing(for: stranger) == 0)
        #expect(tally.servingPriority(for: stranger) == 0)
        #expect(tally.standings().isEmpty)
    }

    @Test("credits accumulate and priority is the standing")
    func credit() {
        let tally = Tally()
        let peer = PeerID(publicKey: "payer")
        tally.creditStanding(peer: peer, bytes: 1_000)
        tally.creditStanding(peer: peer, bytes: 500)
        #expect(tally.standing(for: peer) == 1_500)
        #expect(tally.servingPriority(for: peer) == 1_500)
    }

    @Test("debits clamp at zero and remove the entry")
    func debitClamps() {
        let tally = Tally()
        let peer = PeerID(publicKey: "payer")
        tally.creditStanding(peer: peer, bytes: 1_000)
        tally.debitStanding(peer: peer, bytes: 400)
        #expect(tally.standing(for: peer) == 600)
        tally.debitStanding(peer: peer, bytes: 600)
        #expect(tally.standing(for: peer) == 0)
        #expect(tally.standings().isEmpty)
        tally.creditStanding(peer: peer, bytes: 10)
        tally.debitStanding(peer: peer, bytes: 5_000)
        #expect(tally.standings().isEmpty)
        let stranger = PeerID(publicKey: "stranger")
        tally.debitStanding(peer: stranger, bytes: 10)
        #expect(tally.standing(for: stranger) == 0)
        #expect(tally.standings().isEmpty)
    }

    @Test("zero and negative amounts are ignored")
    func nonPositiveIgnored() {
        let tally = Tally()
        let peer = PeerID(publicKey: "peer")
        tally.creditStanding(peer: peer, bytes: 0)
        tally.creditStanding(peer: peer, bytes: -5)
        tally.recordUsefulReceived(peer: peer, bytes: 0)
        tally.recordUsefulReceived(peer: peer, bytes: -5)
        #expect(tally.standings().isEmpty)
        #expect(tally.metrics.totalUsefulBytesReceived == 0)
        tally.creditStanding(peer: peer, bytes: 100)
        tally.debitStanding(peer: peer, bytes: 0)
        tally.debitStanding(peer: peer, bytes: -5)
        #expect(tally.standing(for: peer) == 100)
    }

    @Test("credit saturates instead of overflowing")
    func creditSaturates() {
        let tally = Tally()
        let peer = PeerID(publicKey: "payer")
        tally.creditStanding(peer: peer, bytes: .max)
        tally.creditStanding(peer: peer, bytes: 1)
        tally.recordUsefulReceived(peer: peer, bytes: 1)
        #expect(tally.standing(for: peer) == .max)
    }

    @Test("standing does not decay")
    func noDecay() async throws {
        let tally = Tally(config: TallyConfig(decayHalfLife: 0.001))
        let peer = PeerID(publicKey: "payer")
        tally.creditStanding(peer: peer, bytes: 1_000)
        tally.recordUsefulReceived(peer: PeerID(publicKey: "server"), bytes: 1_000)
        try await Task.sleep(for: .milliseconds(50))
        #expect(tally.standing(for: peer) == 1_000)
        #expect(tally.standing(for: PeerID(publicKey: "server")) == 1_000)
    }

    @Test("verified, requested content credits standing; raw traffic does not")
    func reciprocityCredits() {
        let tally = Tally()
        let spammer = PeerID(publicKey: "spammer")
        let server = PeerID(publicKey: "server")
        tally.recordReceived(peer: spammer, bytes: 1_000_000)
        tally.recordSent(peer: spammer, bytes: 1_000_000)
        tally.recordUsefulReceived(peer: server, bytes: 10)
        tally.creditStanding(peer: server, bytes: 5)

        #expect(tally.standing(for: spammer) == 0)
        #expect(tally.standing(for: server) == 15)
        #expect(tally.metrics.totalUsefulBytesReceived == 10)
        #expect(tally.metrics.totalBytesReceived == 1_000_000)
    }

    @Test("protocol violations do not change standing")
    func violationsIgnored() {
        let tally = Tally()
        let peer = PeerID(publicKey: "peer")
        tally.creditStanding(peer: peer, bytes: 1_000)
        tally.recordProtocolViolation(peer: peer)
        #expect(tally.servingPriority(for: peer) == 1_000)
    }

    @Test("exported standings restore into a fresh tally")
    func exportRestore() {
        let tally = Tally()
        let first = PeerID(publicKey: "first")
        let second = PeerID(publicKey: "second")
        tally.creditStanding(peer: first, bytes: 100)
        tally.recordUsefulReceived(peer: second, bytes: 200)
        let exported = tally.standings()
        #expect(exported == [first: 100, second: 200])

        let restored = Tally()
        for (peer, bytes) in exported { restored.creditStanding(peer: peer, bytes: bytes) }
        #expect(restored.standings() == exported)
        #expect(restored.servingPriority(for: second) == 200)
    }

    @Test("standing has no cap: a flood of identities evicts none")
    func noCap() {
        let tally = Tally(config: TallyConfig(maxPeers: 1))
        for index in 0..<50 {
            tally.creditStanding(peer: PeerID(publicKey: "peer-\(index)"), bytes: 1)
        }
        #expect(tally.standings().count == 50)
    }

    @Test("standing never decides whose admission evidence survives")
    func standingDoesNotAffectAdmissionEviction() {
        let tally = Tally(config: TallyConfig(maxPeers: 1))
        for index in 0..<4 {
            tally.recordUsefulReceived(peer: PeerID(publicKey: "credited-\(index)"), bytes: 100)
        }
        // Admission evidence stays least-recently-used: five newcomers, the
        // oldest is evicted, the newest four keep their evidence.
        let newcomers = (0..<5).map { PeerID(publicKey: "newcomer-\($0)") }
        for peer in newcomers { tally.recordReceived(peer: peer, bytes: 100) }
        #expect(tally.admissionScore(for: newcomers[0]) == 0)
        for peer in newcomers.dropFirst() { #expect(tally.admissionScore(for: peer) > 0) }
    }

    @Test("admission eviction is least-recently-used")
    func admissionEvictionIsLRU() {
        let tally = Tally(config: TallyConfig(maxPeers: 1))
        let peers = (0..<5).map { PeerID(publicKey: "peer-\($0)") }
        for peer in peers { tally.recordReceived(peer: peer, bytes: 100) }
        #expect(tally.peerCount == 4)
        #expect(tally.admissionScore(for: peers[0]) == 0)
        for peer in peers.dropFirst() { #expect(tally.admissionScore(for: peer) > 0) }
    }
}
