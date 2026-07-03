import Foundation
import Testing
@testable import PhotosAutomation

/// Exercises the real `NSAppleScript` bridge with trivial scripts (no
/// Photos permission needed). Opt-in because the bridge misbehaves inside
/// test bundles on recent macOS — parallel invocations from the same
/// process flake with error -1751 even for `return "hello"`.
@Suite("NSAppleScriptRunner live", .serialized)
struct NSAppleScriptRunnerTests {
    static let enabled = ProcessInfo.processInfo.environment["PHOTOS_AUTOMATION_INTEGRATION"] == "1"
    static let enabledComment: Comment = "set PHOTOS_AUTOMATION_INTEGRATION=1 to run live AppleScript tests"

    @Test("returns scalar string", .disabled(if: !enabled, enabledComment))
    func scalar() async throws {
        let out = try await NSAppleScriptRunner().run(source: #"return "hello""#)
        #expect(out == "hello")
    }

    @Test("empty result coerces to empty string", .disabled(if: !enabled, enabledComment))
    func emptyResult() async throws {
        let out = try await NSAppleScriptRunner().run(source: "return")
        #expect(out == "")
    }

    @Test("runtime error surfaces as AppleScriptError.runtime", .disabled(if: !enabled, enabledComment))
    func runtimeError() async {
        await #expect(throws: AppleScriptError.runtime("boom")) {
            _ = try await NSAppleScriptRunner().run(source: #"error "boom""#)
        }
    }
}
