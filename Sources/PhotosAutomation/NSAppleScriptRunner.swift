import Foundation

/// Production ``AppleScriptRunner`` backed by `NSAppleScript`.
///
/// Each call to ``run(source:)`` constructs and executes its own
/// `NSAppleScript` on the **main thread**, via ``onMainThread(_:)``.
/// `NSAppleScript` is not `Sendable`, so confining its lifetime to that
/// single hop also keeps the library safe under Swift 6 strict
/// concurrency.
///
/// ## Why the main thread is mandatory
///
/// Every script this package emits begins `tell application "Photos"`,
/// so each one sends an Apple Event and blocks awaiting the reply.
/// AppleScript waits inside Carbon's `AEDefaultActiveProc`, which pumps
/// for that reply with `GetNextEventMatchingMask` — a call that services
/// only the **main** thread's event queue, which is also where the reply
/// is delivered.
///
/// Executed on any other thread the reply goes unserviced while the
/// calling thread sits in `mach_msg`. Measured cost of getting this
/// wrong: a script taking ~0.1s on the main thread took ~32s off it, and
/// on another run had not returned when a 200s test timeout killed it.
/// No error is raised — it simply stalls.
///
/// Self-contained scripts (`return "hello"`) send no Apple Event and
/// complete from any thread, which is what makes this easy to miss.
///
/// ## Consequences for callers
///
/// ``run(source:)`` occupies the main actor for the script's duration,
/// so AppleScript calls serialize. That is correct regardless:
/// `NSAppleScript` is neither `Sendable` nor reentrant, and a single
/// application serializes the events it receives anyway.
///
/// Using `NSAppleScript` rather than shelling out to `osascript` avoids
/// the per-call subprocess cost and the shell-escaping hazards that come
/// with building a command line from untrusted strings.
public struct NSAppleScriptRunner: AppleScriptRunner {
    /// Creates a runner.
    ///
    /// There is no per-instance configuration — all state lives in the
    /// per-call `NSAppleScript` object.
    public init() {}

    /// Hops to the main thread and runs `body` there.
    ///
    /// The single seam through which every `NSAppleScript` invocation
    /// passes, so the main-thread invariant documented above is
    /// established in one place — and can be asserted by tests without
    /// needing Photos.app or an Automation permission grant.
    ///
    /// Typed throws: `body`'s error type is preserved across the hop.
    /// `MainActor.run` only `rethrows` (erasing it to `any Error`), so the
    /// outcome crosses back as a `Result`.
    static func onMainThread<T: Sendable, E: Error>(
        _ body: @MainActor @Sendable () throws(E) -> T,
    ) async throws(E) -> T {
        let result = await MainActor.run { Result { () throws(E) -> T in try body() } }
        return try result.get()
    }

    /// Compiles and executes `source`, returning the scalar result as a
    /// `String`.
    ///
    /// - Parameter source: AppleScript source code.
    /// - Returns: `descriptor.stringValue` of the final descriptor, or
    ///   `""` when the result cannot be coerced to a string.
    /// - Throws: ``AppleScriptError/compile(_:)`` when the source cannot
    ///   be constructed; ``AppleScriptError/runtime(_:)`` when
    ///   AppleScript reports an error at execution time.
    public func run(source: String) async throws(AppleScriptError) -> String {
        try await Self.onMainThread { () throws(AppleScriptError) -> String in
            guard let script = NSAppleScript(source: source) else {
                throw AppleScriptError.compile("Failed to construct NSAppleScript")
            }
            var errorInfo: NSDictionary?
            // The error out-parameter is an AutoreleasingUnsafeMutablePointer.
            let descriptor = unsafe script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String
                    ?? errorInfo[NSAppleScript.errorBriefMessage] as? String
                    ?? "AppleScript error \(errorInfo[NSAppleScript.errorNumber] ?? "?")"
                throw AppleScriptError.runtime(message)
            }
            return descriptor.stringValue ?? ""
        }
    }
}
