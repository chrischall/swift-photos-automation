import Foundation
import Testing
@testable import PhotosAutomation

@Suite struct AppleScriptErrorTests {
    @Test func runtimeDescription() {
        let error = AppleScriptError.runtime("Photos got an error")
        #expect(error.errorDescription == "AppleScript runtime error: Photos got an error")
    }

    @Test func compileDescription() {
        let error = AppleScriptError.compile("bad source")
        #expect(error.errorDescription == "AppleScript compile error: bad source")
    }

    @Test func equatable() {
        #expect(AppleScriptError.runtime("x") == AppleScriptError.runtime("x"))
        #expect(AppleScriptError.runtime("x") != AppleScriptError.compile("x"))
    }
}
