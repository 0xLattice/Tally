# Tally architecture

How Tally turns a caller's observations about a peer into an admission
decision and a serving priority. For what Tally is and how to call it, see
the [README](../README.md).

Tally is process-local policy. The caller supplies an authenticated `PeerID`
and only observations it can attribute to that peer.

```text
authenticated, attributed observations
        |                       |
        v                       v
evidence + local pressure    standing
        |                       |
        v                       v
   allow or deny         serving priority
```

`Tally` is a `Sendable` value backed by shared lock-protected state. Its
public methods perform short synchronous mutations. `CreditLineLedger` is a
separate actor with an independent lifecycle.

## What to record

Record an observation only after the caller can identify the cryptographic
peer that caused it.

| Observation | Tally action |
| --- | --- |
| Authenticated bytes | Record sent or received bytes |
| Requested content from the peer that verified | Record useful received bytes (raises standing) |
| Verified signed protocol violation | Record one violation |
| Empty content response, timeout or failed dial | Keep in service-local state |
| Local rate denial | Record nothing; admission metrics already change |
| Unattributed invalid bytes | Drop the input; charge no peer |

## Evidence

Each peer entry stores sent bytes (`S`), received bytes (`R`), attributable
violations (`V`), challenge work (`W`) and one timestamp. Before mutation or
scoring, every signal decays from that timestamp:

```text
d = 2^(-elapsed / decayHalfLife)
S, R, V, W = d * S, d * R, d * V, d * W
```

One active signal therefore cannot preserve unrelated stale evidence.
Nonpositive byte observations are ignored, and aggregate integer metrics
saturate instead of trapping.

## Admission score

After decay:

```text
C = min((S + R) / exchangeBaseline, 1)
Q = (R + 1) / (S + R + 1)
H = min(W / hardnessBaseline, 1)
K = min(KeyDifficulty.keyWorkBits(peer.publicKey) / powBaseline, 1)

score = clamp((0.50*C*Q + 0.25*H + 0.25*C*K) / (1 + V), 0, 1)
```

| Term | Role |
| --- | --- |
| `C` | Requires meaningful exchange. |
| `Q` | Rewards reciprocity. |
| `H` | Permits bounded bootstrap work. |
| `K` | Identity work. It is multiplied by `C`, so identity work alone earns no history. |
| `V` | Discounts earned evidence. |

An unknown peer scores zero. The absence of violations is not positive
evidence.

## Admission

`shouldAllow(peer:)` is one atomic decision:

1. Consume a token from the peer's request bucket; deny if none is available.
2. Measure current process-wide send pressure.
3. Allow below pressure `0.5`; otherwise require the peer score to reach:

```text
min((pressure - 0.5) * 1.6, 0.8)
```

Pressure is current send-window bytes divided by its configured budget,
clamped to `[0, 2]`. Denial updates metrics only. It does not create evidence
or a protocol violation.

## Standing

Standing is one non-negative integer of bytes per peer, held apart from
evidence. `servingPriority(for:)` returns it as the peer's priority; a peer
with none has priority zero.

- `recordUsefulReceived` and `creditStanding` add to it. The sum saturates at
  the integer maximum.
- `debitStanding` subtracts from it and stops at zero. A peer at zero has no
  entry.
- Nonpositive amounts are ignored.
- It does not decay.
- Sent bytes, received bytes, violations and challenge work do not change it,
  and it does not enter the admission score.

`standings()` returns every positive standing. Tally keeps nothing on disk:
the caller persists the export and restores it with `creditStanding`.

## Challenges and identity work

A challenge binds a random nonce, peer identity, difficulty and expiration.
Verification accepts only the outstanding matching challenge and a solution
whose hash meets the leading-zero-bit target. Success removes the nonce
before crediting work, which prevents replay.

`KeyDifficulty.keyWorkBits(_:)` hashes the canonical raw Ed25519 key and
counts trailing zero bits. Raw hex and canonical `ed01` Multikey spellings
therefore produce the same `PeerID` and measure equally. Key validity remains
a caller concern.

## State lifetime

| State | Bound | Removed by |
| --- | --- | --- |
| Evidence | Bounded least-recently-used map | Eviction, `resetPeer(_:)` |
| Request buckets | Bounded least-recently-used map | Eviction, `resetPeer(_:)` |
| Outstanding challenges | Bounded least-recently-used map | Verification, expiry, eviction, `resetPeer(_:)` |
| Standing | Not bounded; an entry exists only while positive | `debitStanding` reaching zero |
| Credit lines | Not bounded | `removeLine(for:)` |

Eviction forgets local state. It does not condemn a peer. `resetPeer(_:)`
removes one peer's evidence, request bucket and challenges; it leaves
standing and lifetime metrics as they are.

Standing is left unbounded because reaching a positive standing costs paying
or serving useful content. Evicting admission state never depends on
standing.

## Credit lines

`CreditLineLedger` serializes bilateral balances, sequence, thresholds and
settlement history. Its line storage lasts for the actor's caller-controlled
lifetime; only `removeLine(for:)` removes a line, so debt is never silently
evicted. Arithmetic saturates at integer bounds. The host defines service
units and validates settlement. Credit never enters peer evidence, send
pressure or the admission score.

## Related

[Tally invariants](correctness-invariants.md) lists the rules a change must
keep.
