# Tally invariants

The rules every change to Tally must keep. Tally does not authenticate
peers: every recorded observation is already attributed by its caller.
[Tally architecture](architecture.md) explains the mechanisms.

| ID | Invariant | Enforced by |
| --- | --- | --- |
| TALLY-001 | Evidence is peer-global; violations are cryptographically attributable. | Caller contract; `TallyTests` |
| TALLY-002 | Every evidence field decays from one shared timestamp before mutation or scoring. | `PeerEvidence`; `PeerEvidenceTests` |
| TALLY-003 | Unknown peers score zero; absence of violations and unexchanged identity work earn nothing. | `PeerEvidence.admissionScore`; `TallyTests` |
| TALLY-004 | Nonpositive byte observations are ignored and aggregate counters saturate. | `Tally`, `TallyMetrics`; `TallyTests` |
| TALLY-005 | Request-token denial changes metrics, not evidence or reputation. | `Tally.shouldAllow`; `TallyTests` |
| TALLY-006 | Greater send pressure never lowers the admission threshold. | `AdmissionController.passesPressureGate`; `AdmissionControllerTests` |
| TALLY-007 | Every score component and the final score remain finite and bounded. | `PeerEvidence.admissionScore`; `PeerEvidenceTests` |
| TALLY-008 | Challenges are peer-bound, exact, expiring, and consumed before work is credited. | `ChallengeService`; `ChallengeTests` |
| TALLY-009 | Valid raw and `ed01` key spellings share one peer identity and key-work measure. | `KeyDifficulty`, `PeerID`; `TallyTests` |
| TALLY-010 | Evidence, request buckets, and outstanding challenges are bounded; eviction forgets rather than punishes. | `BoundedMap`; `TallyTests`, `AdmissionControllerTests` |
| TALLY-011 | Peer reset affects only that peer and preserves lifetime metrics. | `Tally.resetPeer`; `TallyTests` |
| TALLY-012 | Credit state never affects evidence, pressure, or admission score. | `CreditLineLedger`; `CreditLineTests` |
| TALLY-013 | Credit arithmetic saturates; successful settlement recovers zero without lowering the threshold; nonpositive relay amounts do not mutate state. | `CreditLine`; `CreditLineTests` |
| TALLY-014 | Tally grants no membership, content, storage, consensus, or application authority. | Public API surface |
| TALLY-015 | Standing is non-negative, does not decay, and changes only by credit and debit; evidence never changes it and it never enters the admission score. | `Tally.creditStanding`, `Tally.debitStanding`; `StandingTests` |

## Notes

**TALLY-010.** The bound covers the mutable peer-associated state that
admission uses. Standing and credit lines are not bounded: a standing entry
exists only while positive, and a credit line lasts until `removeLine(for:)`.
Standing never decides whose admission state is evicted.

**TALLY-015.** Credit saturates at the integer maximum, debit stops at zero,
and nonpositive amounts are ignored. `resetPeer(_:)` does not change
standing.
