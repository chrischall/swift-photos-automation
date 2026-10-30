import Synchronization

/// A `Mutex`-guarded box for smuggling results out of PhotoKit's
/// `performChanges` closure, which runs on an arbitrary queue and is
/// `@Sendable` under Swift 6.
///
/// A class rather than a bare `Mutex` because `Mutex` is `~Copyable` and
/// so cannot be captured by the escaping change-block closure.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    var value: Value {
        mutex.withLock { $0 }
    }

    /// Runs `body` with exclusive access to the value — use for any
    /// read-modify-write, which `value` alone cannot make atomic.
    func withLock<Result: Sendable>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try mutex.withLock { try body(&$0) }
    }
}
