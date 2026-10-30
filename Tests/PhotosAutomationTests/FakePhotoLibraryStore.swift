import Foundation
import PhotosAutomation
import Synchronization

/// In-memory PhotoLibraryStore for tests. Records every call and returns
/// configurable canned results; set `errorToThrow` to make any call throw.
///
/// Checked `Sendable`: all mutable state lives behind one `Mutex`, exposed
/// through get/set properties so tests read and configure it as before.
final class FakePhotoLibraryStore: PhotoLibraryStore, Sendable {
    private struct State {
        var albums: [PhotoAlbum] = []
        var searchResults: [PhotoAsset] = []
        var assetsById: [String: PhotoAsset] = [:]
        var exportResult: [URL] = []
        var imageDataResult = Data()
        var createdAlbum = PhotoAlbum(id: "new-album", title: "New", assetCount: 0)
        var importResult: [PhotoAsset] = []
        var copyResult = PhotoCopyResult()
        var errorToThrow: any Error?
        var progressEvents: [PhotoCopyProgress] = []
        var afterEachProgress: (@Sendable () -> Void)?
        var calls: [String] = []
        var lastCriteria: PhotoSearchCriteria?
    }

    private let state = Mutex(State())

    var albums: [PhotoAlbum] {
        get { state.withLock { $0.albums } }
        set { state.withLock { $0.albums = newValue } }
    }

    var searchResults: [PhotoAsset] {
        get { state.withLock { $0.searchResults } }
        set { state.withLock { $0.searchResults = newValue } }
    }

    var assetsById: [String: PhotoAsset] {
        get { state.withLock { $0.assetsById } }
        set { state.withLock { $0.assetsById = newValue } }
    }

    var exportResult: [URL] {
        get { state.withLock { $0.exportResult } }
        set { state.withLock { $0.exportResult = newValue } }
    }

    var imageDataResult: Data {
        get { state.withLock { $0.imageDataResult } }
        set { state.withLock { $0.imageDataResult = newValue } }
    }

    var createdAlbum: PhotoAlbum {
        get { state.withLock { $0.createdAlbum } }
        set { state.withLock { $0.createdAlbum = newValue } }
    }

    var importResult: [PhotoAsset] {
        get { state.withLock { $0.importResult } }
        set { state.withLock { $0.importResult = newValue } }
    }

    var copyResult: PhotoCopyResult {
        get { state.withLock { $0.copyResult } }
        set { state.withLock { $0.copyResult = newValue } }
    }

    var errorToThrow: any Error? {
        get { state.withLock { $0.errorToThrow } }
        set { state.withLock { $0.errorToThrow = newValue } }
    }

    /// Progress events `copyAlbum(…progress:)` reports, in order.
    var progressEvents: [PhotoCopyProgress] {
        get { state.withLock { $0.progressEvents } }
        set { state.withLock { $0.progressEvents = newValue } }
    }

    /// Called after each progress event is delivered, so a test can look
    /// at what the caller did with it.
    var afterEachProgress: (@Sendable () -> Void)? {
        get { state.withLock { $0.afterEachProgress } }
        set { state.withLock { $0.afterEachProgress = newValue } }
    }

    var calls: [String] {
        get { state.withLock { $0.calls } }
        set { state.withLock { $0.calls = newValue } }
    }

    var lastCriteria: PhotoSearchCriteria? {
        get { state.withLock { $0.lastCriteria } }
        set { state.withLock { $0.lastCriteria = newValue } }
    }

    private func record(_ call: String) throws {
        let error = state.withLock { state in
            state.calls.append(call)
            return state.errorToThrow
        }
        if let error {
            throw error
        }
    }

    func listAlbums() async throws -> [PhotoAlbum] {
        try record("listAlbums")
        return albums
    }

    func assets(matching criteria: PhotoSearchCriteria) async throws -> [PhotoAsset] {
        lastCriteria = criteria
        try record("assets(matching:)")
        return searchResults
    }

    func asset(id: String) async throws -> PhotoAsset? {
        try record("asset(\(id))")
        return assetsById[id]
    }

    func assets(ids: [String]) async throws -> [PhotoAsset] {
        try record("assets(ids: \(ids))")
        return ids.compactMap { assetsById[$0] }
    }

    func exportOriginals(ids: [String], to directory: URL) async throws -> [URL] {
        try record("exportOriginals(\(ids), to: \(directory.path))")
        return exportResult
    }

    func imageData(id: String, maxDimension: Int) async throws -> Data {
        try record("imageData(\(id), maxDimension: \(maxDimension))")
        return imageDataResult
    }

    func setDescription(id: String, _ description: String) async throws {
        try record("setDescription(\(id), \(description))")
    }

    func setKeywords(id: String, _ keywords: [String]) async throws {
        try record("setKeywords(\(id), \(keywords))")
    }

    func setRating(id: String, _ stars: Int) async throws {
        try record("setRating(\(id), \(stars))")
    }

    func setLivePhotoPlayback(id: String, enabled: Bool) async throws {
        try record("setLivePhotoPlayback(\(id), \(enabled))")
    }

    func createAlbum(title: String) async throws -> PhotoAlbum {
        try record("createAlbum(\(title))")
        return createdAlbum
    }

    func deleteAlbum(id: String) async throws {
        try record("deleteAlbum(\(id))")
    }

    func add(ids: [String], toAlbum albumId: String) async throws {
        try record("add(\(ids), toAlbum: \(albumId))")
    }

    func remove(ids: [String], fromAlbum albumId: String) async throws {
        try record("remove(\(ids), fromAlbum: \(albumId))")
    }

    func setFavorite(id: String, _ isFavorite: Bool) async throws {
        try record("setFavorite(\(id), \(isFavorite))")
    }

    func importFiles(urls: [URL], toAlbum albumId: String?) async throws -> [PhotoAsset] {
        try record("importFiles(\(urls.map(\.lastPathComponent)), toAlbum: \(albumId ?? "nil"))")
        return importResult
    }

    func copyAlbum(sourceAlbumId: String, targetAlbumId: String, dryRun: Bool) async throws -> PhotoCopyResult {
        try record("copyAlbum(\(sourceAlbumId), \(targetAlbumId), dryRun: \(dryRun))")
        return copyResult
    }

    func copyAlbum(sourceAlbumId: String, targetAlbumId: String, dryRun: Bool, cleanPhantoms: Bool) async throws -> PhotoCopyResult {
        try record("copyAlbum(\(sourceAlbumId), \(targetAlbumId), dryRun: \(dryRun), cleanPhantoms: \(cleanPhantoms))")
        return copyResult
    }

    func copyAlbum(sourceAlbumId: String, targetAlbumId: String, dryRun: Bool, cleanPhantoms: Bool,
                   progress: (@Sendable (PhotoCopyProgress) -> Void)?) async throws -> PhotoCopyResult
    {
        try record("copyAlbum(\(sourceAlbumId), \(targetAlbumId), dryRun: \(dryRun), cleanPhantoms: \(cleanPhantoms))")
        for event in progressEvents {
            progress?(event)
            afterEachProgress?()
        }
        return copyResult
    }
}
