#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(os)
import os
#else
import Synchronization
#endif

#if canImport(os)
struct LockedState<State: Sendable>: Sendable {
    private let _lock: OSAllocatedUnfairLock<State>

    init(initialState: State) {
        _lock = OSAllocatedUnfairLock(initialState: initialState)
    }

    @inline(__always)
    func withLock<T: Sendable>(_ body: @Sendable (inout State) throws -> T) rethrows -> T {
        try _lock.withLock(body)
    }
}
#else
/// `Mutex` is in the standard library everywhere this branch builds, so it
/// needs no more of Foundation than the rest of Tally does.
final class LockedState<State: Sendable>: Sendable {
    private let mutex: Mutex<State>

    init(initialState: State) {
        mutex = Mutex(initialState)
    }

    @inline(__always)
    func withLock<T: Sendable>(_ body: @Sendable (inout State) throws -> T) rethrows -> T {
        try mutex.withLock { state in try body(&state) }
    }
}
#endif
