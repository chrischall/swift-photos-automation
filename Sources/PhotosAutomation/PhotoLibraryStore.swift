import Foundation

/// Abstracts PhotoKit so ``PhotoService`` can be unit-tested without a
/// real Photos library or TCC grant.
///
/// Production implementation is ``PhotoKitStore``; tests inject a fake.
/// Implementations throw ``PhotoServiceError`` (`permissionDenied`,
/// `notFound`, `operationFailed`) — they never throw ``AppleScriptError``.
public protocol PhotoLibraryStore: Sendable {
    /// All user-created albums.
    func listAlbums() async throws -> [PhotoAlbum]
    /// Assets matching `criteria`, newest first, capped at `criteria.limit`.
    func assets(matching criteria: PhotoSearchCriteria) async throws -> [PhotoAsset]
    /// The asset with `id`, or `nil` when it doesn't exist.
    func asset(id: String) async throws -> PhotoAsset?
    /// The assets with the given ids. Unknown ids are silently omitted;
    /// result order is unspecified (callers re-order).
    func assets(ids: [String]) async throws -> [PhotoAsset]
    /// Writes each asset's original resource (photo or video file) into
    /// `directory`, creating it if needed. Returns the written file URLs.
    /// All-or-nothing: throws before writing when any id is unknown, and
    /// removes this call's files when a later write fails.
    func exportOriginals(ids: [String], to directory: URL) async throws -> [URL]
    /// A JPEG rendition of the asset scaled to fit `maxDimension` pixels
    /// on its longest side.
    func imageData(id: String, maxDimension: Int) async throws -> Data
    /// Creates a new top-level album.
    func createAlbum(title: String) async throws -> PhotoAlbum
    /// Deletes the album (not its assets). **Shows a blocking system
    /// confirmation dialog** — call only from interactive contexts, never
    /// an unattended run. Not surfaced through ``PhotoService``.
    func deleteAlbum(id: String) async throws
    /// Adds the assets to the album.
    func add(ids: [String], toAlbum albumId: String) async throws
    /// Removes the assets from the album.
    func remove(ids: [String], fromAlbum albumId: String) async throws
    /// Sets or clears the favorite flag.
    func setFavorite(id: String, _ isFavorite: Bool) async throws
    /// Imports the files at `urls` into the library and optionally into
    /// the album with `albumId`. Returns the created assets.
    func importFiles(urls: [URL], toAlbum albumId: String?) async throws -> [PhotoAsset]
    /// Copy assets from one album into another, duplicating cloud-shared items.
    /// Target cloud-shared members never count as duplicates. When requested,
    /// remove those memberships from the target before applying the copy.
    func copyAlbum(sourceAlbumId: String, targetAlbumId: String, dryRun: Bool) async throws -> PhotoCopyResult
    /// Extended copy operation. Existing store implementations keep working
    /// through the default implementation when phantom cleanup is not asked
    /// for.
    func copyAlbum(sourceAlbumId: String, targetAlbumId: String, dryRun: Bool, cleanPhantoms: Bool) async throws -> PhotoCopyResult
    func copyAlbum(sourceAlbumId: String, targetAlbumId: String, dryRun: Bool, cleanPhantoms: Bool,
                   progress: (@Sendable (PhotoCopyProgress) -> Void)?) async throws -> PhotoCopyResult
}

public extension PhotoLibraryStore {
    func copyAlbum(sourceAlbumId: String, targetAlbumId: String, dryRun: Bool, cleanPhantoms: Bool,
                   progress: (@Sendable (PhotoCopyProgress) -> Void)?) async throws -> PhotoCopyResult {
        try await copyAlbum(sourceAlbumId: sourceAlbumId, targetAlbumId: targetAlbumId,
                            dryRun: dryRun, cleanPhantoms: cleanPhantoms)
    }

    func copyAlbum(sourceAlbumId: String, targetAlbumId: String, dryRun: Bool, cleanPhantoms: Bool) async throws -> PhotoCopyResult {
        guard !cleanPhantoms else {
            throw PhotoServiceError.operationFailed("this Photos store does not support cleaning cloud-shared phantom members")
        }
        return try await copyAlbum(sourceAlbumId: sourceAlbumId, targetAlbumId: targetAlbumId, dryRun: dryRun)
    }
}
