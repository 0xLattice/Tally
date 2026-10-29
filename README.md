# Tally

Local, in-memory peer evidence and admission control for Swift.

Tally answers one narrow question: should this process spend resources on this
peer now? The caller authenticates the peer and supplies attributable evidence;
Tally decays that evidence and combines it with request rate and local send
pressure.

A score is local policy, not shared reputation or application authority.

## Basic use

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

Record a violation only when the surrounding protocol can prove that the
authenticated peer broke it:

```swift
if signatureIsValid && signedRecordBreaksProtocol {
    tally.recordProtocolViolation(peer: peer)
}
```

Timeouts, unavailable content, failed dials, latency, route quality, and local
overload stay with the service that can interpret them. They are not protocol
violations.

## Evidence and admission

Admission uses four evidence classes. Exchange, violations, and challenge work
decay; identity work is derived from the peer key.

| Signal | Meaning |
| --- | --- |
| Sent and received bytes | Authenticated exchange history |
| Protocol violations | Cryptographically attributable misbehavior |
| Challenge work | Verified, peer-bound interactive work |
| Identity work | Canonical work derived from the peer key |

`shouldAllow(peer:)` first consumes a per-peer request token. When process-wide
send pressure is low, that is enough. Under load, the peer must also meet a
rising evidence threshold. Unknown peers can therefore bootstrap while capacity
is available without receiving free trust under pressure.

The exact score and threshold are specified in
[Architecture](docs/architecture.md).

## Interactive work

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

Challenges are peer-bound, expiring, and single-use. Invalid, expired, or
replayed solutions earn nothing.

`KeyDifficulty.keyWorkBits(_:)` is the canonical identity-work measure used by
admission and identity-PoW gates. It measures work; it does not validate keys or
grant authority.

## Credit lines

`CreditLineLedger` provides optional bilateral accounting:

```swift
let ledger = CreditLineLedger(localID: localPeer)
await ledger.establish(with: peer)
await ledger.earnFromRelay(peer: peer, amount: 4_096)
```

Credit is independent from admission evidence. The host defines service value,
validates settlement, and decides how balances affect service.

## Boundary

| Tally owns | Its caller owns |
| --- | --- |
| Decayed peer evidence and admission score | Peer authentication and evidence attribution |
| Per-peer request buckets and send pressure | The work guarded by one admission check |
| Challenge issue, verification, and replay prevention | Where proof of work is required |
| Canonical identity-work measurement | Identity validity and application authority |
| Bilateral balance arithmetic | Pricing, settlement proof, and enforcement |

Tally does not decide content validity, routing, storage, topology, consensus,
or canonicity.

## Documentation

Published at [lattice.build/docs](https://lattice.build/docs/protocol/tally/) from the files below.

- [Architecture](docs/architecture.md)
- [Correctness invariants](docs/correctness-invariants.md)

## Installation

```swift
.package(url: "https://github.com/0xLattice/Tally.git", from: "4.0.0")
```

Tally requires Swift 6 and uses `swift-crypto` for SHA-256.

```sh
swift test
swift run -c release TallyBenchmarks
```
