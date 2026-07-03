import Foundation
@testable import PhotosAutomation
import Testing

struct PhotoServiceSearchTextTests {
    @Test func rejectsEmptyQuery() async {
        let service = PhotoService(store: FakePhotoLibraryStore(), runner: FakeAppleScriptRunner())
        await #expect(throws: PhotoServiceError.invalidInput("query must not be empty")) {
            _ = try await service.searchText("   ")
        }
    }

    @Test func rejectsNonPositiveLimit() async {
        let service = PhotoService(store: FakePhotoLibraryStore(), runner: FakeAppleScriptRunner())
        await #expect(throws: PhotoServiceError.invalidInput("limit must be positive")) {
            _ = try await service.searchText("beach", limit: 0)
        }
    }

    @Test func hydratesIdsInScriptOrder() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById = ["B": PhotoAsset(id: "B"), "A": PhotoAsset(id: "A")]
        let runner = FakeAppleScriptRunner()
        runner.queue("B\nA\n")
        let service = PhotoService(store: store, runner: runner)
        let results = try await service.searchText("beach")
        #expect(results.map(\.id) == ["B", "A"])
    }

    @Test func unknownIdsAreOmitted() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById = ["A": PhotoAsset(id: "A")]
        let runner = FakeAppleScriptRunner()
        runner.queue("A\nGONE\n")
        let service = PhotoService(store: store, runner: runner)
        let results = try await service.searchText("beach")
        #expect(results.map(\.id) == ["A"])
    }

    @Test func emptyScriptOutputReturnsEmptyWithoutStoreCall() async throws {
        let store = FakePhotoLibraryStore()
        let runner = FakeAppleScriptRunner()
        runner.queue("")
        let service = PhotoService(store: store, runner: runner)
        let results = try await service.searchText("nothing")
        #expect(results.isEmpty)
        #expect(store.calls.isEmpty)
    }

    @Test func scriptEmbedsEscapedQueryAndLimit() async throws {
        let runner = FakeAppleScriptRunner()
        let service = PhotoService(store: FakePhotoLibraryStore(), runner: runner)
        _ = try await service.searchText(#"kids "party""#, limit: 7)
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].contains(#"search for "kids \"party\"""#))
        #expect(runner.calls[0].contains("if n > 7 then set n to 7"))
    }

    @Test func parseIdLinesTrimsAndSkipsBlanks() {
        #expect(PhotoService.parseIdLines(" A \n\nB\n") == ["A", "B"])
    }
}
