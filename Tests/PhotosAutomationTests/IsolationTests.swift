import Foundation
@testable import PhotosAutomation
import Testing

/// The package builds with `NonisolatedNonsendingByDefault`: a plain
/// `async` function runs on its caller's actor. ``PhotoService`` adds no
/// hop of its own, so a store decides where its work runs — which is why
/// ``PhotoKitStore``'s methods are `@concurrent` (PhotoKit fetches block)
/// while a cheap store, like this test's, stays on the caller.
@Suite(.serialized)
struct IsolationTests {
    /// Records whether each call ran on the main thread.
    final class ThreadRecordingStore: PhotoLibraryStore {
        let onMain = Locked<[Bool]>([])

        private func record() {
            let isMain = Thread.isMainThread
            onMain.withLock { $0.append(isMain) }
        }

        func listAlbums() async throws -> [PhotoAlbum] {
            record()
            return []
        }

        func assets(matching _: PhotoSearchCriteria) async throws -> [PhotoAsset] { [] }
        func asset(id _: String) async throws -> PhotoAsset? { nil }
        func assets(ids _: [String]) async throws -> [PhotoAsset] { [] }
        func exportOriginals(ids _: [String], to _: URL) async throws -> [URL] { [] }
        func imageData(id _: String, maxDimension _: Int) async throws -> Data { Data() }
        func createAlbum(title: String) async throws -> PhotoAlbum { PhotoAlbum(id: "a", title: title, assetCount: 0) }
        func deleteAlbum(id _: String) async throws {}
        func add(ids _: [String], toAlbum _: String) async throws {}
        func remove(ids _: [String], fromAlbum _: String) async throws {}
        func setFavorite(id _: String, _: Bool) async throws {}
        func importFiles(urls _: [URL], toAlbum _: String?) async throws -> [PhotoAsset] { [] }
        func copyAlbum(sourceAlbumId _: String, targetAlbumId _: String, dryRun _: Bool) async throws -> PhotoCopyResult {
            PhotoCopyResult()
        }
    }

    @MainActor
    @Test func `a caller-isolated store runs on the main actor when called from it`() async throws {
        let store = ThreadRecordingStore()
        _ = try await PhotoService(store: store, runner: FakeAppleScriptRunner()).listAlbums()
        #expect(store.onMain.value == [true])
    }

    @MainActor
    @Test func `the AppleScript main-thread hop works from a main-actor caller`() async {
        #expect(await NSAppleScriptRunner.onMainThread { Thread.isMainThread })
    }
}
