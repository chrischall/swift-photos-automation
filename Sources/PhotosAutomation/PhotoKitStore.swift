import Foundation
import Photos

/// Production ``PhotoLibraryStore`` backed by PhotoKit.
///
/// Requires Photos library access (TCC). The first call from an
/// unauthorized process triggers the system permission prompt; a denied
/// state surfaces as ``PhotoServiceError/permissionDenied``.
///
/// > Note: The process needs a usage description to request access. App
/// > bundles declare `NSPhotoLibraryUsageDescription` in Info.plist;
/// > bare executables (like apple-swift-mcp) embed one via the
/// > `-sectcreate __TEXT __info_plist` linker flag.
public struct PhotoKitStore: PhotoLibraryStore {
    /// Creates a store. Stateless — all state lives in PhotoKit.
    public init() {}

    // MARK: - Authorization

    /// Ensures read/write authorization, requesting it when undetermined.
    func ensureAuthorized() async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            throw PhotoServiceError.permissionDenied
        }
    }

    // MARK: - Reads

    public func listAlbums() async throws -> [PhotoAlbum] {
        try await ensureAuthorized()
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: nil
        )
        var albums: [PhotoAlbum] = []
        for i in 0..<collections.count {
            let collection = collections.object(at: i)
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            albums.append(PhotoAlbum(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "",
                assetCount: count
            ))
        }
        return albums
    }

    public func assets(matching criteria: PhotoSearchCriteria) async throws -> [PhotoAsset] {
        try await ensureAuthorized()
        let options = PHFetchOptions()
        var predicates: [NSPredicate] = []
        if let start = criteria.startDate {
            predicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
        }
        if let end = criteria.endDate {
            predicates.append(NSPredicate(format: "creationDate <= %@", end as NSDate))
        }
        if let type = criteria.mediaType {
            predicates.append(NSPredicate(format: "mediaType == %d", Self.phMediaType(type).rawValue))
        }
        if criteria.favoritesOnly {
            predicates.append(NSPredicate(format: "favorite == YES"))
        }
        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = criteria.limit

        let fetch: PHFetchResult<PHAsset>
        if let albumId = criteria.albumId {
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId], options: nil
            ).firstObject else {
                throw PhotoServiceError.notFound("album \(albumId)")
            }
            fetch = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            fetch = PHAsset.fetchAssets(with: options)
        }
        var out: [PhotoAsset] = []
        for i in 0..<fetch.count {
            out.append(Self.photoAsset(from: fetch.object(at: i)))
        }
        return out
    }

    public func asset(id: String) async throws -> PhotoAsset? {
        try await ensureAuthorized()
        guard let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        return Self.photoAsset(from: phAsset)
    }

    public func assets(ids: [String]) async throws -> [PhotoAsset] {
        try await ensureAuthorized()
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var out: [PhotoAsset] = []
        for i in 0..<fetch.count {
            out.append(Self.photoAsset(from: fetch.object(at: i)))
        }
        return out
    }

    // MARK: - Mapping

    /// Maps a `PHAsset` to the library's value type. Title, description,
    /// and keywords stay `nil` — PhotoKit does not expose them; the
    /// service hydrates them via AppleScript when asked for one asset.
    static func photoAsset(from asset: PHAsset) -> PhotoAsset {
        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first { $0.type == .photo || $0.type == .video } ?? resources.first
        return PhotoAsset(
            id: asset.localIdentifier,
            originalFilename: primary?.originalFilename,
            creationDate: asset.creationDate,
            mediaType: Self.mediaType(from: asset.mediaType),
            isFavorite: asset.isFavorite,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude
        )
    }

    static func mediaType(from ph: PHAssetMediaType) -> PhotoMediaType {
        switch ph {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        default: return .unknown
        }
    }

    static func phMediaType(_ type: PhotoMediaType) -> PHAssetMediaType {
        switch type {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .unknown: return .unknown
        }
    }

    // MARK: - Writes (implemented in later tasks)

    public func exportOriginals(ids: [String], to directory: URL) async throws -> [URL] {
        fatalError("implemented in Task 10")
    }

    public func imageData(id: String, maxDimension: Int) async throws -> Data {
        fatalError("implemented in Task 10")
    }

    public func createAlbum(title: String) async throws -> PhotoAlbum {
        fatalError("implemented in Task 11")
    }

    public func deleteAlbum(id: String) async throws {
        fatalError("implemented in Task 11")
    }

    public func add(ids: [String], toAlbum albumId: String) async throws {
        fatalError("implemented in Task 11")
    }

    public func remove(ids: [String], fromAlbum albumId: String) async throws {
        fatalError("implemented in Task 11")
    }

    public func setFavorite(id: String, _ isFavorite: Bool) async throws {
        fatalError("implemented in Task 11")
    }

    public func importFiles(urls: [URL], toAlbum albumId: String?) async throws -> [PhotoAsset] {
        fatalError("implemented in Task 11")
    }
}
