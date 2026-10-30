import Foundation
import Photos
@testable import PhotosAutomation
import Testing

/// macOS 27 additions: Live Photo playback, the original-resource choice,
/// the root folder, and `ProgressManager` progress for album copies.
struct PhotoServiceMacOS27Tests {
    private func make() -> (PhotoService, FakePhotoLibraryStore, FakeAppleScriptRunner) {
        let store = FakePhotoLibraryStore()
        let runner = FakeAppleScriptRunner()
        return (PhotoService(store: store, runner: runner), store, runner)
    }

    // MARK: Live Photo playback

    @Test(arguments: [true, false])
    func `live photo playback goes to the store`(enabled: Bool) async throws {
        let (service, store, runner) = make()
        try await service.setLivePhotoPlayback(id: " A ", enabled: enabled)
        #expect(store.calls == ["setLivePhotoPlayback(A, \(enabled))"])
        #expect(runner.calls.isEmpty)
    }

    @Test func `live photo playback refuses a blank id before the store`() async {
        let (service, store, _) = make()
        await #expect(throws: PhotoServiceError.invalidInput("id must not be empty")) {
            try await service.setLivePhotoPlayback(id: "  ", enabled: false)
        }
        #expect(store.calls.isEmpty)
    }

    @Test func `a store without live photo support throws`() async {
        let service = PhotoService(store: IsolationTests.ThreadRecordingStore(), runner: FakeAppleScriptRunner())
        await #expect(throws: PhotoServiceError.operationFailed("this Photos store cannot change Live Photo playback")) {
            try await service.setLivePhotoPlayback(id: "A", enabled: false)
        }
    }

    // MARK: Asset fields

    @Test func `new asset fields default to a plain compressed still`() {
        let asset = PhotoAsset(id: "A")
        #expect(asset.isLivePhoto == false)
        #expect(asset.originalResource == .compressed)
    }

    @Test func `original resource choices map from PhotoKit`() {
        #expect(PhotoKitStore.originalResource(from: .compressed) == .compressed)
        #expect(PhotoKitStore.originalResource(from: .raw) == .raw)
    }

    @Test func `original resource raw values are stable`() {
        #expect(PhotoOriginalResource.allCases.map(\.rawValue) == ["compressed", "raw"])
    }

    // MARK: Album paths

    @Test func `a folder nests its title under the parent path`() {
        #expect(PhotoKitStore.folderPath(parent: "", title: "Trips", isRoot: false) == "Trips")
        #expect(PhotoKitStore.folderPath(parent: "Trips", title: "2026", isRoot: false) == "Trips/2026")
        #expect(PhotoKitStore.folderPath(parent: "Trips", title: nil, isRoot: false) == "Trips/")
    }

    @Test func `the root folder adds nothing to album paths`() {
        #expect(PhotoKitStore.folderPath(parent: "", title: "Albums", isRoot: true) == "")
        #expect(PhotoKitStore.folderPath(parent: "Trips", title: "Albums", isRoot: true) == "Trips")
    }

    // MARK: copyAlbum with Subprogress

    @Test func `copy album still reports through the callback`() async throws {
        let (service, store, _) = make()
        store.progressEvents = [
            PhotoCopyProgress(total: 4, done: 1, remaining: 3, failed: 0),
            PhotoCopyProgress(total: 4, done: 4, remaining: 0, failed: 1),
        ]
        let seen = Locked<[PhotoCopyProgress]>([])
        _ = try await service.copyAlbum(sourceAlbumId: "s", targetAlbumId: "t") { event in
            seen.withLock { $0.append(event) }
        }
        #expect(seen.value == store.progressEvents)
    }

    @Test func `copy album drives a subprogress to completion`() async throws {
        let (service, store, _) = make()
        store.progressEvents = [
            PhotoCopyProgress(total: 4, done: 1, remaining: 3, failed: 0),
            PhotoCopyProgress(total: 4, done: 2, remaining: 2, failed: 1),
            PhotoCopyProgress(total: 4, done: 4, remaining: 0, failed: 1),
        ]
        store.copyResult.addedByReference = 3
        let parent = ProgressManager(totalCount: 2)
        let fractions = Locked<[Double]>([])
        store.afterEachProgress = { fractions.withLock { $0.append(parent.fractionCompleted) } }

        let result = try await service.copyAlbum(
            sourceAlbumId: " s ", targetAlbumId: "t", dryRun: false, cleanPhantoms: true,
            subprogress: parent.subprogress(assigningCount: 1),
        )

        #expect(result.addedByReference == 3)
        #expect(store.calls == ["copyAlbum(s, t, dryRun: false, cleanPhantoms: true)"])
        // The copy is half of the parent's work: 1/4, 2/4, 4/4 of that half.
        #expect(fractions.value == [0.125, 0.25, 0.5])
        #expect(parent.completedCount == 1)
    }

    @Test func `an empty copy still completes its subprogress`() async throws {
        let (service, store, _) = make()
        store.progressEvents = [PhotoCopyProgress(total: 0, done: 0, remaining: 0, failed: 0)]
        let parent = ProgressManager(totalCount: 1)
        _ = try await service.copyAlbum(sourceAlbumId: "s", targetAlbumId: "t",
                                        subprogress: parent.subprogress(assigningCount: 1))
        #expect(parent.isFinished)
    }

    /// Foundation completes a child's share of the parent when the child
    /// manager is released, success or not; the thrown error is what tells
    /// the caller the copy failed.
    @Test func `a failing copy throws and releases its share of the parent`() async {
        let (service, store, _) = make()
        store.errorToThrow = PhotoServiceError.notFound("album s")
        let parent = ProgressManager(totalCount: 1)
        await #expect(throws: PhotoServiceError.notFound("album s")) {
            _ = try await service.copyAlbum(sourceAlbumId: "s", targetAlbumId: "t",
                                            subprogress: parent.subprogress(assigningCount: 1))
        }
        #expect(parent.completedCount == 1)
    }
}
