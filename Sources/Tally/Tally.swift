#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Local accounting and admission over caller-attributed peer-global evidence.
public struct Tally: Sendable {
    private let _state: LockedState<State>
    private let config: TallyConfig

    public init(config: TallyConfig = .default) {
        self.config = config
        self._state = LockedState(initialState: State(config: config))
    }

    public func recordSent(peer: PeerID, bytes: Int) {
        guard bytes > 0 else { return }
        _state.withLock { state in
            let now = ContinuousClock.now
            state.admission.recordSentBytes(bytes, at: now)
            state.mutateEvidence(for: peer, at: now) {
                $0.recordSent(bytes, at: now, halfLife: config.decayHalfLife)
            }
            state.metrics.totalBytesSent.addSaturating(bytes)
        }
    }

    public func recordReceived(peer: PeerID, bytes: Int) {
        guard bytes > 0 else { return }
        _state.withLock { state in
            let now = ContinuousClock.now
            state.mutateEvidence(for: peer, at: now) {
                $0.recordReceived(bytes, at: now, halfLife: config.decayHalfLife)
            }
            state.metrics.totalBytesReceived.addSaturating(bytes)
        }
    }

    /// Credits content this node requested from `peer` and verified to the
    /// peer's standing. Only verified, solicited content counts.
    public func recordUsefulReceived(peer: PeerID, bytes: Int) {
        guard bytes > 0 else { return }
        _state.withLock { state in
            state.creditStanding(peer: peer, bytes: bytes)
            state.metrics.totalUsefulBytesReceived.addSaturating(bytes)
        }
    }

    /// Raises `peer`'s standing by `bytes`. Standing does not decay; it falls
    /// only by `debitStanding`.
    public func creditStanding(peer: PeerID, bytes: Int) {
        guard bytes > 0 else { return }
        _state.withLock { state in
            state.creditStanding(peer: peer, bytes: bytes)
        }
    }

    /// Lowers `peer`'s standing by `bytes`, stopping at zero. A peer at zero
    /// has no entry.
    public func debitStanding(peer: PeerID, bytes: Int) {
        guard bytes > 0 else { return }
        _state.withLock { state in
            guard let current = state.standing[peer] else { return }
            state.standing[peer] = current > bytes ? current - bytes : nil
        }
    }

    public func standing(for peer: PeerID) -> Int {
        _state.withLock { $0.standing[peer] ?? 0 }
    }

    /// Every positive standing, for persisting across restarts;
    /// `creditStanding` restores each one.
    public func standings() -> [PeerID: Int] {
        _state.withLock { $0.standing }
    }

    /// Orders peers when a host must choose whom to serve: the peer's
    /// standing. Zero for a peer with none.
    public func servingPriority(for peer: PeerID) -> Double {
        Double(standing(for: peer))
    }

    public func recordProtocolViolation(peer: PeerID) {
        _state.withLock { state in
            let now = ContinuousClock.now
            state.mutateEvidence(for: peer, at: now) {
                $0.recordProtocolViolation(at: now, halfLife: config.decayHalfLife)
            }
        }
    }

    public func shouldAllow(peer: PeerID) -> Bool {
        _state.withLock { state in
            let now = ContinuousClock.now
            guard state.admission.consumeRequestToken(peer: peer, at: now) else {
                state.metrics.denied.addSaturating(1)
                return false
            }

            let pressure = state.admission.ratePressure(at: now)
            let allowed: Bool
            if pressure < 0.5 {
                allowed = true
            } else {
                let score = state.admissionScore(for: peer, at: now, config: config)
                allowed = state.admission.passesPressureGate(
                    admissionScore: score,
                    pressure: pressure
                )
            }

            if allowed {
                state.metrics.allowed.addSaturating(1)
            } else {
                state.metrics.denied.addSaturating(1)
            }
            return allowed
        }
    }

    public func admissionScore(for peer: PeerID) -> Double {
        _state.withLock { state in
            state.admissionScore(for: peer, at: .now, config: config)
        }
    }

    public func ratePressure() -> Double {
        _state.withLock { state in
            state.admission.ratePressure(at: .now)
        }
    }

    public func resetPeer(_ peer: PeerID) {
        _state.withLock { state in
            state.evidence.removeValue(forKey: peer)
            state.admission.removePeer(peer)
            state.challenges.removeChallenges(for: peer)
        }
    }

    public var peerCount: Int {
        _state.withLock { $0.evidence.count }
    }

    public var metrics: TallyMetrics {
        _state.withLock { $0.metrics }
    }

    public func issueChallenge(for peer: PeerID) -> Challenge {
        _state.withLock { state in
            let challenge = state.challenges.issue(for: peer)
            state.metrics.challengesIssued.addSaturating(1)
            return challenge
        }
    }

    public func verifyChallenge(_ challenge: Challenge, solution: Data, peer: PeerID) -> Bool {
        _state.withLock { state in
            guard state.challenges.verify(challenge, solution: solution, peer: peer) else {
                return false
            }
            let now = ContinuousClock.now
            state.mutateEvidence(for: peer, at: now) {
                $0.recordChallengeWork(
                    challenge.difficulty,
                    at: now,
                    halfLife: config.decayHalfLife
                )
            }
            state.metrics.challengesVerified.addSaturating(1)
            return true
        }
    }
}

extension Tally {
    struct State: Sendable {
        var evidence: BoundedMap<PeerID, PeerEvidence>
        /// Not bounded: an entry exists only while positive, and reaching
        /// positive costs paying or serving useful content.
        var standing: [PeerID: Int] = [:]
        var admission: AdmissionController
        var challenges: ChallengeService
        var metrics = TallyMetrics()

        init(config: TallyConfig) {
            self.evidence = BoundedMap(capacity: config.boundedPeerStateCapacity)
            self.admission = AdmissionController(config: config)
            self.challenges = ChallengeService(config: config)
        }

        mutating func mutateEvidence(
            for peer: PeerID,
            at now: ContinuousClock.Instant,
            _ mutation: (inout PeerEvidence) -> Void
        ) {
            var peerEvidence = evidence.value(forKey: peer) ?? PeerEvidence(now: now)
            mutation(&peerEvidence)
            evidence.setValue(peerEvidence, forKey: peer)
        }

        mutating func creditStanding(peer: PeerID, bytes: Int) {
            let (sum, overflow) = (standing[peer] ?? 0).addingReportingOverflow(bytes)
            standing[peer] = overflow ? .max : sum
        }

        mutating func admissionScore(
            for peer: PeerID,
            at now: ContinuousClock.Instant,
            config: TallyConfig
        ) -> Double {
            guard var peerEvidence = evidence.value(forKey: peer) else { return 0 }
            let score = peerEvidence.admissionScore(for: peer, at: now, config: config)
            evidence.setValue(peerEvidence, forKey: peer)
            return score
        }
    }
}
