# Tally

Tally is a Swift library that keeps local, in-memory accounts of the peers a
process talks to and answers two questions about them: should this process
spend resources on this peer now, and whom should it serve first when it is
busy. In Lattice, the networking layer ([Ivy](https://lattice.build/docs/protocol/ivy/))
asks Tally before it serves a peer, and the node credits and persists each
peer's standing.

A score or a standing is local policy. It is not shared reputation and grants
no authority.

## Quick example

```swift
import Tally

let tally = Tally()
let peer = PeerID(publicKey: authenticatedPublicKey)

tally.recordReceived(peer: peer, bytes: request.count)

guard tally.shouldAllow(peer: peer) else {
    return
}

let response = makeResponse()
tally.recordSent(peer: peer, bytes: response.count)
```

The caller authenticates the peer first. Tally never does.

## Key concepts

| Concept | What it is | API |
| --- | --- | --- |
| Evidence | Decaying per-peer history: bytes exchanged, proven violations, challenge work. | `recordSent`, `recordReceived`, `recordProtocolViolation` |
| Admission | One allow-or-deny decision from the peer's request rate, its evidence and the process's send pressure. | `shouldAllow(peer:)` |
| Standing | A byte balance per peer that orders whom a busy host serves first. | `servingPriority(for:)`, `creditStanding`, `debitStanding` |
| Challenge | Proof of work a new peer can do to earn evidence. | `issueChallenge`, `verifyChallenge` |
| Identity work | Work measured from the peer's key. | `KeyDifficulty.keyWorkBits(_:)` |
| Credit line | Optional two-party balance accounting, separate from all of the above. | `CreditLineLedger` |

[Tally architecture](docs/architecture.md) gives the score formula, the
admission threshold and the lifetime of each kind of state.

### Evidence and admission

`shouldAllow(peer:)` first consumes a per-peer request token. When
process-wide send pressure is low, that is enough. Under load, the peer must
also meet an evidence threshold that rises with pressure. An unknown peer can
therefore start while capacity is available, and gets no free trust under
pressure.

Record a violation only when the surrounding protocol can prove that the
authenticated peer broke it:

```swift
if signatureIsValid && signedRecordBreaksProtocol {
    tally.recordProtocolViolation(peer: peer)
}
```

Timeouts, unavailable content, failed dials, latency, route quality and local
overload are not protocol violations. They stay with the service that can
interpret them.

### Standing

Standing is a non-negative byte balance per peer. `servingPriority(for:)`
returns it.

| Call | Effect |
| --- | --- |
| `recordUsefulReceived(peer:bytes:)` | Raises standing by content this process requested from the peer and verified. |
| `creditStanding(peer:bytes:)` | Raises standing. |
| `debitStanding(peer:bytes:)` | Lowers standing, stopping at zero. |
| `standings()` | Returns every positive standing, for the caller to persist. |

Standing does not decay and has no cap. Only positive standings are kept. To
restore after a restart, call `creditStanding` with each exported value.
Admission evidence does not affect standing.

### Challenges

```swift
let challenge = tally.issueChallenge(for: peer)

// Solve away from an event loop or latency-sensitive actor.
if let solution = ChallengeSolver().solve(challenge) {
    let accepted = tally.verifyChallenge(
        challenge,
        solution: solution,
        peer: peer
    )
}
```

Challenges are peer-bound, expiring and single-use. Invalid, expired or
replayed solutions earn nothing.

### Identity work

`KeyDifficulty.keyWorkBits(_:)` is the canonical identity-work measure used
by admission and identity proof-of-work gates. It measures work. It does not
validate keys or grant authority.

### Credit lines

```swift
let ledger = CreditLineLedger(localID: localPeer)
await ledger.establish(with: peer)
await ledger.earnFromRelay(peer: peer, amount: 4_096)
```

Credit is independent of admission evidence and of standing. The host defines
service value, validates settlement, and decides how balances affect service.

## Boundary

| Tally owns | The caller owns |
| --- | --- |
| Decayed peer evidence and admission score | Peer authentication and evidence attribution |
| Per-peer request buckets and send pressure | The work guarded by one admission check |
| Standing arithmetic and export | When to credit or debit standing, and persisting it |
| Challenge issue, verification and replay prevention | Where proof of work is required |
| Canonical identity-work measurement | Identity validity and application authority |
| Bilateral balance arithmetic | Pricing, settlement proof and enforcement |

Tally does not decide content validity, routing, storage, topology, consensus
or canonicity.

## Documentation

Published at [lattice.build/docs](https://lattice.build/docs/protocol/tally/)
from the files below.

| Page | What it covers |
| --- | --- |
| [Tally architecture](docs/architecture.md) | How evidence decays, the score formula, the admission threshold, standing, and how long each kind of state lives. |
| [Tally invariants](docs/correctness-invariants.md) | The rules a change to Tally must keep, each with its ID and the code and tests that enforce it. |

## Install

```swift
.package(url: "https://github.com/0xLattice/Tally.git", from: "4.0.0")
```

Tally requires Swift 6 and uses `swift-crypto` for SHA-256.

```sh
swift test
swift run -c release TallyBenchmarks
```
