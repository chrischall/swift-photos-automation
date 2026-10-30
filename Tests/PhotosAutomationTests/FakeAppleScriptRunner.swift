import Foundation
import PhotosAutomation
import Synchronization

/// In-memory AppleScriptRunner for tests. Records every script it was asked
/// to run, and replies with a queued result or a constant.
///
/// Checked `Sendable`: all mutable state lives behind one `Mutex`.
final class FakeAppleScriptRunner: AppleScriptRunner, Sendable {
    private struct State {
        var responses: [Result<String, AppleScriptError>] = []
        var defaultResponse: Result<String, AppleScriptError>
        var calls: [String] = []
    }

    private let state: Mutex<State>

    init(defaultResponse: Result<String, AppleScriptError> = .success("")) {
        state = Mutex(State(defaultResponse: defaultResponse))
    }

    /// Every script source passed to ``run(source:)``, in call order.
    var calls: [String] {
        state.withLock { $0.calls }
    }

    func run(source: String) async throws(AppleScriptError) -> String {
        let response = state.withLock { state in
            state.calls.append(source)
            return state.responses.isEmpty ? state.defaultResponse : state.responses.removeFirst()
        }
        return try response.get()
    }

    /// Queues a successful result, handed out in FIFO order before
    /// `defaultResponse`.
    func queue(_ result: String) {
        state.withLock { $0.responses.append(.success(result)) }
    }

    /// Queues an ``AppleScriptError/runtime(_:)`` failure.
    func queueError(_ msg: String) {
        state.withLock { $0.responses.append(.failure(.runtime(msg))) }
    }
}
