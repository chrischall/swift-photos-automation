import AppKit
import Foundation
import Photos
import UniformTypeIdentifiers

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
        for i in 0 ..< collections.count {
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
        for i in 0 ..< fetch.count {
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
        for i in 0 ..< fetch.count {
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
        case .image: .image
        case .video: .video
        case .audio: .audio
        default: .unknown
        }
    }

    static func phMediaType(_ type: PhotoMediaType) -> PHAssetMediaType {
        switch type {
        case .image: .image
        case .video: .video
        case .audio: .audio
        case .unknown: .unknown
        }
    }

    // MARK: - Export and image data

    public func exportOriginals(ids: [String], to directory: URL) async throws -> [URL] {
        try await ensureAuthorized()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PhotoServiceError.operationFailed(error.localizedDescription)
        }
        var written: [URL] = []
        for id in ids {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
                throw PhotoServiceError.notFound("asset \(id)")
            }
            let resources = PHAssetResource.assetResources(for: asset)
            guard let resource = resources.first(where: { $0.type == .photo || $0.type == .video })
                ?? resources.first
            else {
                throw PhotoServiceError.operationFailed("asset \(id) has no exportable resource")
            }
            let destination = Self.availableURL(in: directory, filename: resource.originalFilename)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(
                    for: resource, toFile: destination, options: options
                ) { error in
                    if let error {
                        c.resume(throwing: PhotoServiceError.operationFailed(error.localizedDescription))
                    } else {
                        c.resume()
                    }
                }
            }
            written.append(destination)
        }
        return written
    }

    public func imageData(id: String, maxDimension: Int) async throws -> Data {
        try await ensureAuthorized()
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw PhotoServiceError.notFound("asset \(id)")
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // handler fires exactly once
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        let target = CGSize(width: maxDimension, height: maxDimension)
        // Encode to JPEG inside the callback so only Sendable Data crosses
        // the continuation (NSImage is not Sendable).
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            PHImageManager.default().requestImage(
                for: asset, targetSize: target, contentMode: .aspectFit, options: options
            ) { image, info in
                guard let image else {
                    let message = (info?[PHImageErrorKey] as? NSError)?.localizedDescription
                        ?? "image request failed"
                    c.resume(throwing: PhotoServiceError.operationFailed(message))
                    return
                }
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
                else {
                    c.resume(throwing: PhotoServiceError.operationFailed("could not encode JPEG for \(id)"))
                    return
                }
                c.resume(returning: jpeg)
            }
        }
    }

    /// Returns a URL in `directory` for `filename`, appending ` (n)` before
    /// the extension when the name is already taken.
    static func availableURL(in directory: URL, filename: String) -> URL {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: filename).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }

    // MARK: - Writes

    /// Runs a PhotoKit change block, translating failures to
    /// ``PhotoServiceError/operationFailed(_:)``.
    private func performChanges(_ block: @escaping @Sendable () -> Void) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges(block)
        } catch {
            throw PhotoServiceError.operationFailed(error.localizedDescription)
        }
    }

    public func createAlbum(title: String) async throws -> PhotoAlbum {
        try await ensureAuthorized()
        let createdId = Locked<String?>(nil)
        try await performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            createdId.value = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = createdId.value,
              let collection = PHAssetCollection.fetchAssetCollections(
                  withLocalIdentifiers: [id], options: nil
              ).firstObject
        else {
            throw PhotoServiceError.operationFailed("album creation returned no identifier")
        }
        return PhotoAlbum(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? title,
            assetCount: 0
        )
    }

    /// Deletes the album (not its assets).
    ///
    /// > Important: macOS shows a **blocking confirmation dialog** for this
    /// > operation, so it cannot run unattended — the `performChanges`
    /// > completion won't fire until the user responds. Call it only from
    /// > interactive contexts; the integration suite deliberately never does.
    public func deleteAlbum(id: String) async throws {
        try await ensureAuthorized()
        try ensureAlbumExists(id)
        try await performChanges {
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            PHAssetCollectionChangeRequest.deleteAssetCollections(collections)
        }
    }

    public func add(ids: [String], toAlbum albumId: String) async throws {
        try await ensureAuthorized()
        try ensureAssetsExist(ids)
        try ensureAlbumEditable(albumId, operation: .addContent)
        try await performChanges {
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId], options: nil
            ).firstObject,
                let request = PHAssetCollectionChangeRequest(for: collection)
            else { return }
            request.addAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    }

    public func remove(ids: [String], fromAlbum albumId: String) async throws {
        try await ensureAuthorized()
        try ensureAssetsExist(ids)
        try ensureAlbumEditable(albumId, operation: .removeContent)
        try await performChanges {
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId], options: nil
            ).firstObject,
                let request = PHAssetCollectionChangeRequest(for: collection)
            else { return }
            request.removeAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    }

    public func setFavorite(id: String, _ isFavorite: Bool) async throws {
        try await ensureAuthorized()
        try ensureAssetsExist([id])
        try await performChanges {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
            else { return }
            PHAssetChangeRequest(for: asset).isFavorite = isFavorite
        }
    }

    public func importFiles(urls: [URL], toAlbum albumId: String?) async throws -> [PhotoAsset] {
        try await ensureAuthorized()
        if let albumId {
            try ensureAlbumEditable(albumId, operation: .addContent)
        }
        let createdIds = Locked<[String]>([])
        try await performChanges {
            var placeholders: [PHObjectPlaceholder] = []
            for url in urls {
                let isVideo = UTType(filenameExtension: url.pathExtension)?
                    .conforms(to: .movie) ?? false
                let request = isVideo
                    ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                if let placeholder = request?.placeholderForCreatedAsset {
                    placeholders.append(placeholder)
                }
            }
            if let albumId,
               let collection = PHAssetCollection.fetchAssetCollections(
                   withLocalIdentifiers: [albumId], options: nil
               ).firstObject,
               let albumRequest = PHAssetCollectionChangeRequest(for: collection)
            {
                albumRequest.addAssets(placeholders as NSArray)
            }
            createdIds.value = placeholders.map(\.localIdentifier)
        }
        guard createdIds.value.count == urls.count else {
            throw PhotoServiceError.operationFailed(
                "imported \(createdIds.value.count) of \(urls.count) files — unsupported format?"
            )
        }
        let fetched = try await assets(ids: createdIds.value)
        let byId = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return createdIds.value.compactMap { byId[$0] }
    }

    // MARK: - Existence checks

    /// Throws ``PhotoServiceError/notFound(_:)`` when any id is unknown.
    private func ensureAssetsExist(_ ids: [String]) throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard fetch.count == ids.count else {
            var found = Set<String>()
            for i in 0 ..< fetch.count {
                found.insert(fetch.object(at: i).localIdentifier)
            }
            let missing = ids.filter { !found.contains($0) }
            throw PhotoServiceError.notFound("asset(s) \(missing.joined(separator: ", "))")
        }
    }

    /// Throws ``PhotoServiceError/notFound(_:)`` when the album is unknown.
    private func ensureAlbumExists(_ albumId: String) throws {
        guard PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil)
            .firstObject != nil
        else {
            throw PhotoServiceError.notFound("album \(albumId)")
        }
    }

    /// Throws when the album cannot be edited (e.g. a smart album) —
    /// ``PHAssetCollectionChangeRequest`` would silently return `nil` for it
    /// inside the change block.
    private func ensureAlbumEditable(_ albumId: String, operation: PHCollectionEditOperation) throws {
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil)
            .firstObject
        else {
            throw PhotoServiceError.notFound("album \(albumId)")
        }
        guard collection.canPerform(operation) else {
            throw PhotoServiceError.operationFailed("album \(albumId) does not allow this operation")
        }
    }
}
