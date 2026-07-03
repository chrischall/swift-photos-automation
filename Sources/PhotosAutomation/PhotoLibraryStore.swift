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
}
