import Foundation
@testable import PhotosAutomation
import Testing

/// Exercises the real `NSAppleScript` bridge with trivial scripts (no
/// Photos permission needed). Opt-in because the bridge misbehaves inside
/// test bundles on recent macOS — parallel invocations from the same
/// process flake with error -1751 even for `return "hello"`.
@Suite("NSAppleScriptRunner live", .serialized)
struct NSAppleScriptRunnerTests {
    static let enabled = ProcessInfo.processInfo.environment["PHOTOS_AUTOMATION_INTEGRATION"] == "1"
    static let enabledComment: Comment = "set PHOTOS_AUTOMATION_INTEGRATION=1 to run live AppleScript tests"

    @Test(.disabled(if: !enabled, enabledComment))
    func `returns scalar string`() async throws {
        let out = try await NSAppleScriptRunner().run(source: #"return "hello""#)
        #expect(out == "hello")
    }

    @Test(.disabled(if: !enabled, enabledComment))
    func `empty result coerces to empty string`() async throws {
        let out = try await NSAppleScriptRunner().run(source: "return")
        #expect(out == "")
    }

    @Test(.disabled(if: !enabled, enabledComment))
    func `runtime error surfaces as AppleScriptError.runtime`() async {
        await #expect(throws: AppleScriptError.runtime("boom")) {
            _ = try await NSAppleScriptRunner().run(source: #"error "boom""#)
        }
    }
}

/// Thread-affinity tests for `NSAppleScriptRunner`.
///
/// `NSAppleScript` must execute on the **main thread**. A script that
/// targets another application (`tell application "Photos" …`) sends an
/// Apple Event and waits for the reply via Carbon's
/// `AEDefaultActiveProc` → `GetNextEventMatchingMask`, which pumps only
/// the *main* thread's event queue — where the reply is delivered. Off
/// the main thread the reply goes unserviced and the call stalls: ~32s
/// measured for a script that takes ~0.1s done correctly, and on another
/// run no return at all before a 200s timeout killed it.
///
/// Self-contained scripts send no Apple Event and succeed from any
/// thread, so the rest of the suite cannot catch this. These assert the
/// invariant directly and need neither Photos.app nor an Automation
/// grant.
///
/// Carries `.serialized` to match the repo's convention for suites
/// touching `NSAppleScriptRunner`. Unlike the live suites it needs no
/// env-var gate: it never reaches the `NSAppleScript` bridge, hopping
/// only plain Swift closures through `onMainThread`, so it is safe and
/// useful on CI — where it is the sole guard against this regression.
@Suite("NSAppleScriptRunner thread affinity", .serialized)
struct NSAppleScriptRunnerThreadAffinityTests {
    @Test
    func `script execution is confined to the main thread`() async {
        let ranOnMain = await NSAppleScriptRunner.onMainThread { Thread.isMainThread }
        #expect(
            ranOnMain,
            """
            NSAppleScript must execute on the main thread — Apple Event \
            replies are delivered to the main run loop, so running it \
            elsewhere stalls every `tell application` script.
            """,
        )
    }

    @Test
    func `the result of the main-thread hop reaches the caller`() async {
        let value = await NSAppleScriptRunner.onMainThread { 6 * 7 }
        #expect(value == 42)
    }

    @Test
    func `errors thrown on the main thread propagate to the caller`() async {
        await #expect(throws: AppleScriptError.self) {
            try await NSAppleScriptRunner.onMainThread {
                throw AppleScriptError.compile("boom")
            }
        }
    }
}
