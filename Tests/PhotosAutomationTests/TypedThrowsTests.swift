import Foundation
@testable import PhotosAutomation
import Testing

/// The public `PhotoService` API and the `AppleScriptRunner` protocol use
/// typed throws: `catch` binds a `PhotosError` (or `AppleScriptError`)
/// directly — these would not compile against an untyped `throws`.
struct TypedThrowsTests {
    private struct StoreFailure: LocalizedError {
        var errorDescription: String? { "store exploded" }
    }

    @Test func `validation failures surface as service errors`() async {
        let service = PhotoService(store: FakePhotoLibraryStore(), runner: FakeAppleScriptRunner())
        do {
            _ = try await service.asset(id: " ")
            Issue.record("expected a throw")
        } catch {
            #expect(error == .service(.invalidInput("id must not be empty")))
            #expect(error.serviceError == .invalidInput("id must not be empty"))
        }
    }

    @Test func `store PhotoServiceError is wrapped`() async {
        let store = FakePhotoLibraryStore()
        store.errorToThrow = PhotoServiceError.permissionDenied
        let service = PhotoService(store: store, runner: FakeAppleScriptRunner())
        do {
            _ = try await service.listAlbums()
            Issue.record("expected a throw")
        } catch {
            #expect(error == .service(.permissionDenied))
        }
    }

    @Test func `foreign store errors become operationFailed`() async {
        let store = FakePhotoLibraryStore()
        store.errorToThrow = StoreFailure()
        let service = PhotoService(store: store, runner: FakeAppleScriptRunner())
        do {
            try await service.setFavorite(id: "A", true)
            Issue.record("expected a throw")
        } catch {
            #expect(error == .service(.operationFailed("store exploded")))
        }
    }

    @Test func `store cancellation surfaces as cancelled`() async {
        let store = FakePhotoLibraryStore()
        store.errorToThrow = CancellationError()
        let service = PhotoService(store: store, runner: FakeAppleScriptRunner())
        do {
            _ = try await service.listAssets()
            Issue.record("expected a throw")
        } catch {
            #expect(error == .cancelled)
        }
    }

    @Test func `apple script failures surface as appleScript errors`() async {
        let runner = FakeAppleScriptRunner()
        runner.queueError("no permission")
        let service = PhotoService(store: FakePhotoLibraryStore(), runner: runner)
        do {
            try await service.setTitle(id: "A", "x")
            Issue.record("expected a throw")
        } catch {
            #expect(error == .appleScript(.runtime("no permission")))
            #expect(error.appleScriptError == .runtime("no permission"))
        }
    }

    @Test func `searchText wraps apple script failures`() async {
        let runner = FakeAppleScriptRunner()
        runner.queueError("Photos is not running")
        let service = PhotoService(store: FakePhotoLibraryStore(), runner: runner)
        do {
            _ = try await service.searchText("beach")
            Issue.record("expected a throw")
        } catch {
            #expect(error == .appleScript(.runtime("Photos is not running")))
        }
    }

    @Test func `runner protocol throws AppleScriptError`() async {
        let runner: any AppleScriptRunner = FakeAppleScriptRunner(defaultResponse: .failure(.compile("bad")))
        do {
            _ = try await runner.run(source: "x")
            Issue.record("expected a throw")
        } catch {
            #expect(error == .compile("bad"))
        }
    }

    @Test func `main-thread hop keeps the error type`() async {
        do {
            try await NSAppleScriptRunner.onMainThread { () throws(AppleScriptError) in
                throw .runtime("typed")
            }
            Issue.record("expected a throw")
        } catch {
            #expect(error == .runtime("typed"))
        }
    }
}
