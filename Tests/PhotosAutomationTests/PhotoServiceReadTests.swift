import Foundation
@testable import PhotosAutomation
import Testing

struct PhotoServiceReadTests {
    private func makeService(
        store: FakePhotoLibraryStore = FakePhotoLibraryStore(),
        runner: FakeAppleScriptRunner = FakeAppleScriptRunner(),
    ) -> PhotoService {
        PhotoService(store: store, runner: runner)
    }

    // MARK: listAlbums

    @Test func `copy album passes ids and dry run through`() async throws {
        let store = FakePhotoLibraryStore()
        store.copyResult.addedByReference = 2
        let result = try await makeService(store: store).copyAlbum(
            sourceAlbumId: "shared", targetAlbumId: "local", dryRun: true, cleanPhantoms: true,
        )
        #expect(result.addedByReference == 2)
        #expect(store.calls.contains("copyAlbum(shared, local, dryRun: true, cleanPhantoms: true)"))
    }

    @Test func `list albums returns store albums`() async throws {
        let store = FakePhotoLibraryStore()
        store.albums = [PhotoAlbum(id: "a1", title: "Trips", assetCount: 3)]
        let albums = try await makeService(store: store).listAlbums()
        #expect(albums == [PhotoAlbum(id: "a1", title: "Trips", assetCount: 3)])
    }

    // MARK: listAssets

    @Test func `list assets builds criteria from arguments`() async throws {
        let store = FakePhotoLibraryStore()
        _ = try await makeService(store: store).listAssets(albumId: "alb1", limit: 10)
        #expect(store.lastCriteria == PhotoSearchCriteria(albumId: "alb1", limit: 10))
    }

    @Test func `list assets defaults`() async throws {
        let store = FakePhotoLibraryStore()
        _ = try await makeService(store: store).listAssets()
        #expect(store.lastCriteria == PhotoSearchCriteria())
    }

    @Test func `list assets rejects non positive limit`() async {
        await #expect(throws: PhotosError.service(.invalidInput("limit must be positive"))) {
            _ = try await self.makeService().listAssets(limit: 0)
        }
    }

    @Test func `list assets rejects empty album id`() async {
        await #expect(throws: PhotosError.service(.invalidInput("albumId must not be empty"))) {
            _ = try await self.makeService().listAssets(albumId: "  ")
        }
    }

    // MARK: search

    @Test func `search passes criteria through`() async throws {
        let store = FakePhotoLibraryStore()
        store.searchResults = [PhotoAsset(id: "X")]
        let criteria = PhotoSearchCriteria(favoritesOnly: true, limit: 5)
        let results = try await makeService(store: store).search(criteria: criteria)
        #expect(results == [PhotoAsset(id: "X")])
        #expect(store.lastCriteria == criteria)
    }

    @Test func `search rejects non positive limit`() async {
        await #expect(throws: PhotosError.service(.invalidInput("limit must be positive"))) {
            _ = try await self.makeService().search(criteria: PhotoSearchCriteria(limit: -1))
        }
    }

    @Test func `search rejects blank album id`() async {
        await #expect(throws: PhotosError.service(.invalidInput("albumId must not be empty"))) {
            _ = try await self.makeService().search(criteria: PhotoSearchCriteria(albumId: "  "))
        }
    }

    // MARK: asset(id:)

    @Test func `asset rejects empty id`() async {
        await #expect(throws: PhotosError.service(.invalidInput("id must not be empty"))) {
            _ = try await self.makeService().asset(id: "")
        }
    }

    @Test func `asset not found throws`() async {
        await #expect(throws: PhotosError.service(.notFound("asset missing-id"))) {
            _ = try await self.makeService().asset(id: "missing-id")
        }
    }

    @Test func `asset survives apple script failure`() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById["A"] = PhotoAsset(id: "A")
        let runner = FakeAppleScriptRunner()
        runner.queueError("Photos is not running")
        let asset = try await makeService(store: store, runner: runner).asset(id: "A")
        #expect(asset.id == "A")
        #expect(asset.title == nil)
    }

    @Test func `escape for apple script`() {
        #expect(PhotoService.escapeForAppleScript(#"say "hi" \now"#) == #"say \"hi\" \\now"#)
    }
}
