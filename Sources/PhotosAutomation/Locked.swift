import Foundation

/// A minimal lock-guarded box for smuggling results out of PhotoKit's
/// `performChanges` closure, which runs on an arbitrary queue and is
/// `@Sendable` under Swift 6.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
