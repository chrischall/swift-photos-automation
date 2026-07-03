import Foundation
import PhotosAutomation

/// In-memory PhotoLibraryStore for tests. Records every call and returns
/// configurable canned results; set `errorToThrow` to make any call throw.
final class FakePhotoLibraryStore: PhotoLibraryStore, @unchecked Sendable {
    var albums: [PhotoAlbum] = []
    var searchResults: [PhotoAsset] = []
    var assetsById: [String: PhotoAsset] = [:]
    var exportResult: [URL] = []
    var imageDataResult = Data()
    var createdAlbum = PhotoAlbum(id: "new-album", title: "New", assetCount: 0)
    var importResult: [PhotoAsset] = []
    var errorToThrow: Error?

    private(set) var calls: [String] = []
    private(set) var lastCriteria: PhotoSearchCriteria?

    private func record(_ call: String) throws {
        calls.append(call)
        if let errorToThrow { throw errorToThrow }
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
}
