import Foundation
@testable import PhotosAutomation
import Testing

struct PhotoServiceReadTests {
    private func makeService(
        store: FakePhotoLibraryStore = FakePhotoLibraryStore(),
        runner: FakeAppleScriptRunner = FakeAppleScriptRunner()
    ) -> PhotoService {
        PhotoService(store: store, runner: runner)
    }

    // MARK: listAlbums

    @Test func listAlbumsReturnsStoreAlbums() async throws {
        let store = FakePhotoLibraryStore()
        store.albums = [PhotoAlbum(id: "a1", title: "Trips", assetCount: 3)]
        let albums = try await makeService(store: store).listAlbums()
        #expect(albums == [PhotoAlbum(id: "a1", title: "Trips", assetCount: 3)])
    }

    // MARK: listAssets

    @Test func listAssetsBuildsCriteriaFromArguments() async throws {
        let store = FakePhotoLibraryStore()
        _ = try await makeService(store: store).listAssets(albumId: "alb1", limit: 10)
        #expect(store.lastCriteria == PhotoSearchCriteria(albumId: "alb1", limit: 10))
    }

    @Test func listAssetsDefaults() async throws {
        let store = FakePhotoLibraryStore()
        _ = try await makeService(store: store).listAssets()
        #expect(store.lastCriteria == PhotoSearchCriteria())
    }

    @Test func listAssetsRejectsNonPositiveLimit() async {
        await #expect(throws: PhotoServiceError.invalidInput("limit must be positive")) {
            _ = try await self.makeService().listAssets(limit: 0)
        }
    }

    @Test func listAssetsRejectsEmptyAlbumId() async {
        await #expect(throws: PhotoServiceError.invalidInput("albumId must not be empty")) {
            _ = try await self.makeService().listAssets(albumId: "  ")
        }
    }

    // MARK: search

    @Test func searchPassesCriteriaThrough() async throws {
        let store = FakePhotoLibraryStore()
        store.searchResults = [PhotoAsset(id: "X")]
        let criteria = PhotoSearchCriteria(favoritesOnly: true, limit: 5)
        let results = try await makeService(store: store).search(criteria: criteria)
        #expect(results == [PhotoAsset(id: "X")])
        #expect(store.lastCriteria == criteria)
    }

    @Test func searchRejectsNonPositiveLimit() async {
        await #expect(throws: PhotoServiceError.invalidInput("limit must be positive")) {
            _ = try await self.makeService().search(criteria: PhotoSearchCriteria(limit: -1))
        }
    }

    @Test func searchRejectsBlankAlbumId() async {
        await #expect(throws: PhotoServiceError.invalidInput("albumId must not be empty")) {
            _ = try await self.makeService().search(criteria: PhotoSearchCriteria(albumId: "  "))
        }
    }

    // MARK: asset(id:)

    @Test func assetRejectsEmptyId() async {
        await #expect(throws: PhotoServiceError.invalidInput("id must not be empty")) {
            _ = try await self.makeService().asset(id: "")
        }
    }

    @Test func assetNotFoundThrows() async {
        await #expect(throws: PhotoServiceError.notFound("asset missing-id")) {
            _ = try await self.makeService().asset(id: "missing-id")
        }
    }

    @Test func assetHydratesMetadataFromAppleScript() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById["A/L0/001"] = PhotoAsset(id: "A/L0/001")
        let runner = FakeAppleScriptRunner()
        runner.queue("Sunset\tGolden hour\tbeach,sunset")
        let asset = try await makeService(store: store, runner: runner).asset(id: "A/L0/001")
        #expect(asset.title == "Sunset")
        #expect(asset.itemDescription == "Golden hour")
        #expect(asset.keywords == ["beach", "sunset"])
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].contains(#"media item id "A/L0/001""#))
    }

    @Test func assetEmptyMetadataStaysNil() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById["A"] = PhotoAsset(id: "A")
        let runner = FakeAppleScriptRunner()
        runner.queue("\t\t")
        let asset = try await makeService(store: store, runner: runner).asset(id: "A")
        #expect(asset.title == nil)
        #expect(asset.itemDescription == nil)
        #expect(asset.keywords == nil)
    }

    @Test func assetSurvivesAppleScriptFailure() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById["A"] = PhotoAsset(id: "A")
        let runner = FakeAppleScriptRunner()
        runner.queueError("Photos is not running")
        let asset = try await makeService(store: store, runner: runner).asset(id: "A")
        #expect(asset.id == "A")
        #expect(asset.title == nil)
    }

    // MARK: parse helper

    @Test func parseMetadataLineMalformedReturnsNils() {
        let meta = PhotoService.parseMetadataLine("only-one-field")
        #expect(meta.title == nil)
        #expect(meta.description == nil)
        #expect(meta.keywords == nil)
    }

    @Test func escapeForAppleScript() {
        #expect(PhotoService.escapeForAppleScript(#"say "hi" \now"#) == #"say \"hi\" \\now"#)
    }
}
