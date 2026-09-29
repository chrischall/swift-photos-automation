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
        guard status == .authorized else {
            throw PhotoServiceError.permissionDenied
        }
    }

    // MARK: - Reads

    public func listAlbums() async throws -> [PhotoAlbum] {
        try await ensureAuthorized()
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: nil
        )
        let sharedCollections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumCloudShared, options: nil
        )
        var paths: [String: String] = [:]
        func walk(_ list: PHCollectionList, prefix: String) {
            let children = PHCollectionList.fetchCollections(in: list, options: nil)
            for index in 0 ..< children.count {
                let child = children.object(at: index)
                let path = prefix.isEmpty ? (child.localizedTitle ?? "") : "\(prefix)/\(child.localizedTitle ?? "")"
                if let album = child as? PHAssetCollection { paths[album.localIdentifier] = path }
                if let folder = child as? PHCollectionList { walk(folder, prefix: path) }
            }
        }
        let roots = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        for index in 0 ..< roots.count {
            if let folder = roots.object(at: index) as? PHCollectionList { walk(folder, prefix: folder.localizedTitle ?? "") }
            else if let album = roots.object(at: index) as? PHAssetCollection { paths[album.localIdentifier] = album.localizedTitle ?? "" }
        }
        var albums: [PhotoAlbum] = []
        for (result, shared) in [(collections, false), (sharedCollections, true)] {
            for i in 0 ..< result.count {
                let collection = result.object(at: i)
                let count = PHAsset.fetchAssets(in: collection, options: Self.assetFetchOptions()).count
                albums.append(PhotoAlbum(id: collection.localIdentifier, title: collection.localizedTitle ?? "",
                                         assetCount: count, path: paths[collection.localIdentifier], isShared: shared))
            }
        }
        return albums
    }

    public func assets(matching criteria: PhotoSearchCriteria) async throws -> [PhotoAsset] {
        try await ensureAuthorized()
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
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
        guard let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.assetFetchOptions()).firstObject else {
            return nil
        }
        return Self.photoAsset(from: phAsset)
    }

    public func assets(ids: [String]) async throws -> [PhotoAsset] {
        try await ensureAuthorized()
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.assetFetchOptions())
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
            longitude: asset.location?.coordinate.longitude,
            sourceType: asset.sourceType.contains(.typeCloudShared) ? "cloudShared" : "userLibrary"
        )
    }

    private static func assetFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        return options
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
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.assetFetchOptions()).firstObject else {
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
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.assetFetchOptions()).firstObject else {
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
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.assetFetchOptions())
        for index in 0 ..< assets.count where assets.object(at: index).sourceType.contains(.typeCloudShared) {
            throw PhotoServiceError.operationFailed("shared-stream assets cannot be added by reference; use photos_copy_album to import local copies")
        }
        try ensureAlbumEditable(albumId, operation: .addContent)
        try await performChanges {
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId], options: nil
            ).firstObject,
                let request = PHAssetCollectionChangeRequest(for: collection)
            else { return }
            request.addAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.assetFetchOptions()))
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
            request.removeAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.assetFetchOptions()))
        }
    }

    public func setFavorite(id: String, _ isFavorite: Bool) async throws {
        try await ensureAuthorized()
        try ensureAssetsExist([id])
        try await performChanges {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.assetFetchOptions()).firstObject
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
            // The change block already committed the ones that worked;
            // name them so a caller can retry only the rest.
            let created = createdIds.value.isEmpty ? "none" : createdIds.value.joined(separator: ", ")
            throw PhotoServiceError.operationFailed(
                "imported \(createdIds.value.count) of \(urls.count) files — unsupported format? created ids: \(created)"
            )
        }
        let fetched = try await assets(ids: createdIds.value)
        let byId = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return createdIds.value.compactMap { byId[$0] }
    }

    public func copyAlbum(sourceAlbumId: String, targetAlbumId: String, dryRun: Bool = false) async throws -> PhotoCopyResult {
        try await ensureAuthorized()
        guard let source = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [sourceAlbumId], options: nil).firstObject else {
            throw PhotoServiceError.notFound("album \(sourceAlbumId)")
        }
        try ensureAlbumEditable(targetAlbumId, operation: .addContent)
        guard let targetCollection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [targetAlbumId], options: nil).firstObject,
              targetCollection.assetCollectionType == .album, targetCollection.assetCollectionSubtype == .albumRegular else {
            throw PhotoServiceError.invalidInput("targetAlbumId must identify a regular local album")
        }
        guard source.localIdentifier != targetAlbumId else {
            throw PhotoServiceError.invalidInput("sourceAlbumId and targetAlbumId must differ")
        }
        let options = Self.assetFetchOptions()
        let sourceFetch = PHAsset.fetchAssets(in: source, options: options)
        let target = targetCollection
        let targetFetch = PHAsset.fetchAssets(in: target, options: options)
        var existingIds = Set<String>()
        var existingKeys = Set<String>()
        for i in 0 ..< targetFetch.count {
            let asset = targetFetch.object(at: i)
            existingIds.insert(asset.localIdentifier)
            existingKeys.insert(Self.copyIdentity(asset))
        }
        var result = PhotoCopyResult()
        var pendingReferences: [PHAsset] = []
        var pendingCopies: [(PHAsset, [(PHAssetResource, URL)])] = []
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("PhotosCopy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        func commitBatch() async {
            guard !pendingReferences.isEmpty || !pendingCopies.isEmpty else { return }
            let references = pendingReferences
            let copies = pendingCopies
            pendingReferences.removeAll()
            pendingCopies.removeAll()
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let targetFetch = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [targetAlbumId], options: nil)
                    guard let target = targetFetch.firstObject, let albumRequest = PHAssetCollectionChangeRequest(for: target) else { return }
                    if !references.isEmpty {
                        albumRequest.addAssets(references as NSArray)
                    }
                    var placeholders: [PHObjectPlaceholder] = []
                    for (asset, resources) in copies {
                        let request = PHAssetCreationRequest.forAsset()
                        request.creationDate = asset.creationDate
                        request.location = asset.location
                        for (resource, url) in resources {
                            let resourceOptions = PHAssetResourceCreationOptions()
                            resourceOptions.originalFilename = resource.originalFilename
                            request.addResource(with: resource.type, fileURL: url, options: resourceOptions)
                        }
                        if let placeholder = request.placeholderForCreatedAsset { placeholders.append(placeholder) }
                    }
                    albumRequest.addAssets(placeholders as NSArray)
                }
                result.addedByReference += references.count
                result.importedAsCopies += copies.count
            } catch {
                for asset in references + copies.map(\.0) {
                    result.failures.append(PhotoCopyFailure(assetId: asset.localIdentifier, reason: error.localizedDescription))
                }
            }
        }

        for index in 0 ..< sourceFetch.count {
            let asset = sourceFetch.object(at: index)
            if existingIds.contains(asset.localIdentifier) || existingKeys.contains(Self.copyIdentity(asset)) {
                result.skippedDuplicates += 1
                continue
            }
            if dryRun {
                if asset.sourceType.contains(.typeCloudShared) { result.importedAsCopies += 1 }
                else { result.addedByReference += 1 }
                continue
            }
            if !asset.sourceType.contains(.typeCloudShared) {
                pendingReferences.append(asset)
            } else {
                let resources = PHAssetResource.assetResources(for: asset).filter { [.photo, .video, .pairedVideo].contains($0.type) }
                guard !resources.isEmpty else {
                    result.failures.append(PhotoCopyFailure(assetId: asset.localIdentifier, reason: "no original photo or video resources"))
                    continue
                }
                do {
                    var staged: [(PHAssetResource, URL)] = []
                    for resource in resources {
                        let url = tempRoot.appendingPathComponent(UUID().uuidString + "-" + resource.originalFilename)
                        let requestOptions = PHAssetResourceRequestOptions()
                        requestOptions.isNetworkAccessAllowed = true
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: requestOptions) { error in
                                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                            }
                        }
                        staged.append((resource, url))
                    }
                    pendingCopies.append((asset, staged))
                } catch {
                    result.failures.append(PhotoCopyFailure(assetId: asset.localIdentifier, reason: error.localizedDescription))
                }
            }
            existingIds.insert(asset.localIdentifier)
            existingKeys.insert(Self.copyIdentity(asset))
            if pendingReferences.count + pendingCopies.count >= 25 { await commitBatch() }
        }
        await commitBatch()
        return result
    }

    private static func copyIdentity(_ asset: PHAsset) -> String {
        let resource = PHAssetResource.assetResources(for: asset).first { $0.type == .photo || $0.type == .video }
        let date = asset.creationDate.map { String($0.timeIntervalSince1970) } ?? ""
        return "\(resource?.originalFilename ?? "")|\(date)|\(asset.pixelWidth)x\(asset.pixelHeight)"
    }

    // MARK: - Existence checks

    /// Throws ``PhotoServiceError/notFound(_:)`` when any id is unknown.
    private func ensureAssetsExist(_ ids: [String]) throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.assetFetchOptions())
        // The fetch holds each asset once, so compare against distinct ids.
        guard fetch.count == Set(ids).count else {
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
