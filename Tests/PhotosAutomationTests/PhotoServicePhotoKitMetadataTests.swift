import Foundation
import Photos
@testable import PhotosAutomation
import Testing

/// Descriptions, keywords and ratings go through the store (PhotoKit's
/// macOS 27 metadata APIs); only titles and free-text search still need
/// AppleScript.
struct PhotoServicePhotoKitMetadataTests {
    private func make() -> (PhotoService, FakePhotoLibraryStore, FakeAppleScriptRunner) {
        let store = FakePhotoLibraryStore()
        let runner = FakeAppleScriptRunner()
        return (PhotoService(store: store, runner: runner), store, runner)
    }

    // MARK: writes

    @Test func `set description goes to the store, not AppleScript`() async throws {
        let (service, store, runner) = make()
        try await service.setDescription(id: " A ", "Golden hour")
        #expect(store.calls == ["setDescription(A, Golden hour)"])
        #expect(runner.calls.isEmpty)
    }

    @Test func `set keywords goes to the store, not AppleScript`() async throws {
        let (service, store, runner) = make()
        try await service.setKeywords(id: "A", ["beach", "sun\"set"])
        #expect(store.calls == [#"setKeywords(A, ["beach", "sun\"set"])"#])
        #expect(runner.calls.isEmpty)
    }

    @Test(arguments: [0, 1, 5])
    func `set rating goes to the store`(rating: Int) async throws {
        let (service, store, runner) = make()
        try await service.setRating(id: "A", rating)
        #expect(store.calls == ["setRating(A, \(rating))"])
        #expect(runner.calls.isEmpty)
    }

    @Test(arguments: [-1, 6])
    func `a rating outside 0 to 5 is refused before the store`(rating: Int) async {
        let (service, store, _) = make()
        await #expect(throws: PhotoServiceError.invalidInput("rating must be 0–5 (0 clears it)")) {
            try await service.setRating(id: "A", rating)
        }
        #expect(store.calls.isEmpty)
    }

    @Test func `set title still uses AppleScript`() async throws {
        let (service, store, runner) = make()
        try await service.setTitle(id: "A", "Sunset")
        #expect(store.calls.isEmpty)
        #expect(runner.calls.count == 1)
    }

    @Test func `store write errors propagate`() async {
        let (service, store, _) = make()
        store.errorToThrow = PhotoServiceError.notFound("asset(s) A")
        await #expect(throws: PhotoServiceError.notFound("asset(s) A")) {
            try await service.setKeywords(id: "A", ["x"])
        }
    }

    // MARK: asset(id:)

    @Test func `asset keeps PhotoKit metadata and reads only the title over AppleScript`() async throws {
        let (service, store, runner) = make()
        store.assetsById["A"] = PhotoAsset(
            id: "A", itemDescription: "Golden hour", keywords: ["beach"], rating: 4, fileSize: 1234,
        )
        runner.queue("Sunset")
        let asset = try await service.asset(id: "A")
        #expect(asset.title == "Sunset")
        #expect(asset.itemDescription == "Golden hour")
        #expect(asset.keywords == ["beach"])
        #expect(asset.rating == 4)
        #expect(asset.fileSize == 1234)
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].contains(#"name of media item id "A""#))
        #expect(!runner.calls[0].contains("description"))
        #expect(!runner.calls[0].contains("keywords"))
    }

    @Test func `asset keeps PhotoKit metadata when AppleScript fails`() async throws {
        let (service, store, runner) = make()
        store.assetsById["A"] = PhotoAsset(id: "A", itemDescription: "Golden hour", keywords: ["beach"])
        runner.queueError("Photos is not running")
        let asset = try await service.asset(id: "A")
        #expect(asset.title == nil)
        #expect(asset.itemDescription == "Golden hour")
        #expect(asset.keywords == ["beach"])
    }

    @Test func `an empty title stays nil`() async throws {
        let (service, store, runner) = make()
        store.assetsById["A"] = PhotoAsset(id: "A")
        runner.queue("")
        #expect(try await service.asset(id: "A").title == nil)
    }

    @Test func `the title script escapes the id`() {
        #expect(PhotoService.titleScript(id: #"A"B"#).contains(#"media item id "A\"B""#))
    }

    // MARK: PhotoKit mapping helpers

    @Test func `keyword edits turn the current list into the desired one`() {
        let edits = PhotoKitStore.keywordEdits(current: ["a", "b", "b", "c"], desired: ["c", "d", "d", "a"])
        #expect(edits.remove == ["b"])
        #expect(edits.add == ["d"])
    }

    @Test func `no keyword edits when nothing changes`() {
        let edits = PhotoKitStore.keywordEdits(current: ["a", "b"], desired: ["b", "a"])
        #expect(edits.remove.isEmpty)
        #expect(edits.add.isEmpty)
    }

    @Test func `an unset PhotoKit rating reads as nil`() {
        #expect(PhotoKitStore.stars(from: .unset) == nil)
        #expect(PhotoKitStore.stars(from: .one) == 1)
        #expect(PhotoKitStore.stars(from: .five) == 5)
    }

    @Test func `star counts map onto PhotoKit ratings`() {
        #expect(PhotoKitStore.rating(stars: 0) == .unset)
        #expect(PhotoKitStore.rating(stars: 3) == .three)
        #expect(PhotoKitStore.rating(stars: 5) == .five)
        #expect(PhotoKitStore.rating(stars: 6) == nil)
    }
}
