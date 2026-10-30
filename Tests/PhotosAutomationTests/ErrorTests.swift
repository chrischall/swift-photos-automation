import Foundation
@testable import PhotosAutomation
import Testing

struct AppleScriptErrorTests {
    @Test func `runtime description`() {
        let error = AppleScriptError.runtime("Photos got an error")
        #expect(error.errorDescription == "AppleScript runtime error: Photos got an error")
    }

    @Test func `compile description`() {
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
        #expect(PhotoServiceError.fullAccessRequired.errorDescription
            == "Full Photos library access is required for shared album copying — Limited access is not sufficient. Grant Full Access in System Settings → Privacy & Security → Photos")
        #expect(PhotoServiceError.operationFailed("boom").errorDescription
            == "Photos operation failed: boom")
    }

    @Test func equatable() {
        #expect(PhotoServiceError.permissionDenied == PhotoServiceError.permissionDenied)
        #expect(PhotoServiceError.notFound("a") != PhotoServiceError.notFound("b"))
    }
}

/// The validators use typed throws, so `catch` binds a `PhotoServiceError`
/// directly — these would not compile against an untyped `throws`.
struct ValidatorTypedThrowsTests {
    @Test func `validateIds throws PhotoServiceError`() {
        do {
            _ = try PhotoService.validateIds([])
            Issue.record("expected a throw")
        } catch {
            #expect(error == .invalidInput("ids must not be empty"))
        }
    }

    @Test func `validatePositive throws PhotoServiceError`() {
        do {
            try PhotoService.validatePositive(0)
            Issue.record("expected a throw")
        } catch {
            #expect(error == .invalidInput("limit must be positive"))
        }
    }

    @Test func `validateNonEmpty throws PhotoServiceError`() {
        do {
            try PhotoService.validateNonEmpty(" ", name: "id")
            Issue.record("expected a throw")
        } catch {
            #expect(error == .invalidInput("id must not be empty"))
        }
    }
}

struct PhotosErrorTests {
    @Test func `wraps both underlying error types`() {
        #expect(PhotosError.appleScript(.runtime("x")).appleScriptError == .runtime("x"))
        #expect(PhotosError.appleScript(.runtime("x")).serviceError == nil)
        #expect(PhotosError.service(.permissionDenied).serviceError == .permissionDenied)
        #expect(PhotosError.service(.permissionDenied).appleScriptError == nil)
        #expect(PhotosError.cancelled.serviceError == nil)
        #expect(PhotosError.cancelled.appleScriptError == nil)
    }

    @Test func `description is the wrapped error's`() {
        #expect(PhotosError.appleScript(.compile("bad")).errorDescription
            == AppleScriptError.compile("bad").errorDescription)
        #expect(PhotosError.service(.notFound("asset X")).errorDescription
            == PhotoServiceError.notFound("asset X").errorDescription)
        #expect(PhotosError.cancelled.errorDescription == "The Photos operation was cancelled")
    }

    @Test func `localizedDescription is unchanged for wrapped errors`() {
        let wrapped: any Error = PhotosError.service(.invalidInput("id must not be empty"))
        #expect(wrapped.localizedDescription == "Invalid input: id must not be empty")
    }

    @Test func equatable() {
        #expect(PhotosError.appleScript(.runtime("x")) == .appleScript(.runtime("x")))
        #expect(PhotosError.appleScript(.runtime("x")) != .service(.operationFailed("x")))
    }

    @Test func `normalizes any error`() {
        #expect(PhotosError(PhotoServiceError.notFound("a")) == .service(.notFound("a")))
        #expect(PhotosError(AppleScriptError.runtime("r")) == .appleScript(.runtime("r")))
        #expect(PhotosError(PhotosError.cancelled) == .cancelled)
        #expect(PhotosError(CancellationError()) == .cancelled)
        struct Opaque: LocalizedError {
            var errorDescription: String? { "disk on fire" }
        }
        #expect(PhotosError(Opaque()) == .service(.operationFailed("disk on fire")))
    }
}
