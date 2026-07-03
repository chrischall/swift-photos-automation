import Foundation
@testable import PhotosAutomation
import Testing

struct AppleScriptErrorTests {
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

struct PhotoServiceErrorTests {
    @Test func descriptions() {
        #expect(PhotoServiceError.invalidInput("id must not be empty").errorDescription
            == "Invalid input: id must not be empty")
        #expect(PhotoServiceError.notFound("asset X").errorDescription
            == "Not found: asset X")
        #expect(PhotoServiceError.permissionDenied.errorDescription
            == "Photos library access denied — grant access in System Settings → Privacy & Security → Photos")
        #expect(PhotoServiceError.operationFailed("boom").errorDescription
            == "Photos operation failed: boom")
    }

    @Test func equatable() {
        #expect(PhotoServiceError.permissionDenied == PhotoServiceError.permissionDenied)
        #expect(PhotoServiceError.notFound("a") != PhotoServiceError.notFound("b"))
    }
}
