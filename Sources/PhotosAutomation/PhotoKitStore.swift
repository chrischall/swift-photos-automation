public import Foundation
import AppKit
import CoreLocation
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
    private let provenanceStore: PhotoCopyProvenanceStore

    /// Creates a store with durable provenance for assets copied from shared albums.
    public init(provenanceStore: PhotoCopyProvenanceStore = PhotoCopyProvenanceStore()) {
        self.provenanceStore = provenanceStore
    }

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
            with: .album, subtype: .albumRegular, options: nil,
        )
        let sharedCollections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumCloudShared, options: nil,
        )
        var paths: [String: String] = [:]
        func walk(_ list: PHCollectionList, prefix: String) {
            let children = PHCollectionList.fetchCollections(in: list, options: nil)
            for index in 0 ..< children.count {
                let child = children.object(at: index)
                let path = prefix.isEmpty ? (child.localizedTitle ?? "") : "\(prefix)/\(child.localizedTitle ?? "")"
                if let album = child as? PHAssetCollection {
                    paths[album.localIdentifier] = path
                }
                if let folder = child as? PHCollectionList {
                    walk(folder, prefix: path)
                }
            }
        }
        let roots = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        for index in 0 ..< roots.count {
            if let folder = roots.object(at: index) as? PHCollectionList {
                walk(
                    folder,
                    prefix: folder.localizedTitle ?? "",
                )
            } else if let album = roots.object(at: index) as? PHAssetCollection {
                paths[album.localIdentifier] = album.localizedTitle ?? ""
            }
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
                withLocalIdentifiers: [albumId], options: nil,
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

    /// Maps a `PHAsset` to the library's value type, description, keywords,
    /// rating and size included (macOS 27 PhotoKit; the fetch options
    /// prefetch the extended metadata, so a listing reads it in bulk). The
    /// title stays `nil`: PhotoKit has no API for it, so the service reads
    /// it over AppleScript when asked for one asset.
    static func photoAsset(from asset: PHAsset) -> PhotoAsset {
        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first { $0.type == .photo || $0.type == .video } ?? resources.first
        let metadata = asset.extendedMetadata
        return PhotoAsset(
            id: asset.localIdentifier,
            originalFilename: primary.map(Self.filename(of:)),
            creationDate: asset.creationDate,
            mediaType: Self.mediaType(from: asset.mediaType),
            isFavorite: asset.isFavorite,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            sourceType: asset.sourceType.contains(.typeCloudShared) ? .cloudShared : .userLibrary,
            itemDescription: metadata.caption.flatMap { $0.isEmpty ? nil : $0 },
            keywords: metadata.keywords.isEmpty ? nil : metadata.keywords,
            rating: Self.stars(from: asset.rating),
            fileSize: primary?.dataSize,
        )
    }

    /// The star count for a PhotoKit rating; `nil` when unrated.
    static func stars(from rating: PHAsset.Rating) -> Int? {
        switch rating {
        case .one: 1
        case .two: 2
        case .three: 3
        case .four: 4
        case .five: 5
        default: nil
        }
    }

    /// The PhotoKit rating for a star count, `0` meaning unrated; `nil`
    /// outside 0–5.
    static func rating(stars: Int) -> PHAsset.Rating? {
        switch stars {
        case 0: .unset
        case 1: .one
        case 2: .two
        case 3: .three
        case 4: .four
        case 5: .five
        default: nil
        }
    }

    private static func assetFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        // Captions and keywords for every fetched asset in one go, rather
        // than a fault per asset when photoAsset(from:) reads them.
        options.prefetchAssetExtendedMetadata = true
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
        // Resolve every asset and its resource before writing anything, so an
        // unknown id or a resource-less asset fails with nothing on disk.
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.assetFetchOptions())
        var byId: [String: PHAsset] = [:]
        for i in 0 ..< fetch.count {
            let asset = fetch.object(at: i)
            byId[asset.localIdentifier] = asset
        }
        let missing = Self.missingIDs(requested: ids, found: Set(byId.keys))
        guard missing.isEmpty else {
            throw PhotoServiceError.notFound("asset(s) \(missing.joined(separator: ", "))")
        }
        let resources: [(id: String, resource: PHAssetResource)] = try ids.map { id in
            let all = PHAssetResource.assetResources(for: byId[id]!)
            guard let resource = all.first(where: { $0.type == .photo || $0.type == .video }) ?? all.first else {
                throw PhotoServiceError.operationFailed("asset \(id) has no exportable resource")
            }
            return (id, resource)
        }
        // A write can still fail mid-way (e.g. an iCloud download); then the
        // files already written by this call are removed rather than orphaned.
        return try await Self.writeAllOrNothing(resources) { item in
            let destination = Self.availableURL(in: directory, filename: Self.filename(of: item.resource))
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            do {
                try await PHAssetResourceManager.default().writeData(
                    for: item.resource, toFile: destination, options: options,
                )
            } catch {
                throw PhotoServiceError.operationFailed(error.localizedDescription)
            }
            return destination
        }
    }

    /// Runs `write` for each item in order and returns the URLs it wrote.
    /// If any write throws, the files already written by this call are
    /// removed before the error is rethrown — the export is all-or-nothing.
    static func writeAllOrNothing<Item>(
        _ items: [Item], _ write: (Item) async throws -> URL,
    ) async throws -> [URL] {
        var written: [URL] = []
        do {
            for item in items {
                try await written.append(write(item))
            }
        } catch {
            for url in written {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
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
        // Never ask for more than the cap or the asset's own size: `.exact`
        // would otherwise upscale to the target and allocate a huge bitmap.
        let dimension = PhotoService.renditionDimension(
            requested: maxDimension, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
        )
        let target = CGSize(width: dimension, height: dimension)
        // Encode to JPEG inside the callback so only Sendable Data crosses
        // the continuation (NSImage is not Sendable).
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            PHImageManager.default().requestImage(
                for: asset, targetSize: target, contentMode: .aspectFit, options: options,
            ) { image, info in
                guard let image else {
                    let message = (info?[PHImageErrorKey] as? NSError)?.localizedDescription
                        ?? "image request failed"
                    c.resume(throwing: PhotoServiceError.operationFailed(message))
                    return
                }
                // Encode straight from the CGImage — no TIFF round-trip, so
                // the bitmap is not buffered a second time.
                // `forProposedRect` is an UnsafeMutablePointer<NSRect>; nil is safe.
                guard let cgImage = unsafe image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let jpeg = NSBitmapImageRep(cgImage: cgImage)
                          .representation(using: .jpeg, properties: [.compressionFactor: 0.85])
                else {
                    c.resume(throwing: PhotoServiceError.operationFailed("could not encode JPEG for \(id)"))
                    return
                }
                c.resume(returning: jpeg)
            }
        }
    }

    /// The resource's file name. `PHAssetResource.filename` (macOS 27)
    /// is optional where the deprecated `originalFilename` was not, so a
    /// nameless resource is named from its type instead.
    static func filename(of resource: PHAssetResource) -> String {
        resource.filename ?? fallbackFilename(uniformTypeIdentifier: resource.uniformTypeIdentifier)
    }

    /// `resource.<ext>` for the type's preferred extension, or `resource`
    /// when the type is unknown.
    static func fallbackFilename(uniformTypeIdentifier: String) -> String {
        UTType(uniformTypeIdentifier)?.preferredFilenameExtension.map { "resource.\($0)" } ?? "resource"
    }

    /// Returns a URL in `directory` for `filename`, appending ` (n)` before
    /// the extension when the name is already taken.
    static func availableURL(in directory: URL, filename: String) -> URL {
        let file = URL(filePath: filename)
        let base = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        var candidate = directory.appending(path: filename)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let name = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appending(path: name)
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
            let id = request.placeholderForCreatedAssetCollection.localIdentifier
            createdId.withLock { $0 = id }
        }
        guard let id = createdId.value,
              let collection = PHAssetCollection.fetchAssetCollections(
                  withLocalIdentifiers: [id], options: nil,
              ).firstObject
        else {
            throw PhotoServiceError.operationFailed("album creation returned no identifier")
        }
        return PhotoAlbum(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? title,
            assetCount: 0,
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
            throw PhotoServiceError.operationFailed(
                "shared-stream assets cannot be added by reference; use photos_copy_album to import local copies",
            )
        }
        try ensureAlbumEditable(albumId, operation: .addContent)
        try await performChanges {
            guard let collection = PHAssetCollection.fetchAssetCollections(
                      withLocalIdentifiers: [albumId], options: nil,
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
                      withLocalIdentifiers: [albumId], options: nil,
                  ).firstObject,
                  let request = PHAssetCollectionChangeRequest(for: collection)
            else { return }
            request.removeAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.assetFetchOptions()))
        }
    }

    public func setDescription(id: String, _ description: String) async throws {
        try await ensureAuthorized()
        _ = try editableAsset(id)
        try await performChanges {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.assetFetchOptions()).firstObject
            else { return }
            // An empty string clears the caption; PhotoKit reads `nil` as
            // "leave it unchanged" (seen live on macOS 27.2).
            PHAssetChangeRequest(for: asset).caption = description
        }
    }

    public func setKeywords(id: String, _ keywords: [String]) async throws {
        try await ensureAuthorized()
        let edits = try Self.keywordEdits(current: editableAsset(id).extendedMetadata.keywords, desired: keywords)
        guard !edits.remove.isEmpty || !edits.add.isEmpty else { return }
        try await performChanges {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.assetFetchOptions()).firstObject
            else { return }
            let request = PHAssetChangeRequest(for: asset)
            for keyword in edits.remove {
                request.removeKeyword(keyword)
            }
            for keyword in edits.add {
                request.addKeyword(keyword)
            }
        }
    }

    public func setRating(id: String, _ stars: Int) async throws {
        guard let rating = Self.rating(stars: stars) else {
            throw PhotoServiceError.invalidInput("rating must be 0–5 (0 clears it)")
        }
        try await ensureAuthorized()
        _ = try editableAsset(id)
        try await performChanges {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.assetFetchOptions()).firstObject
            else { return }
            PHAssetChangeRequest(for: asset).rating = rating
        }
    }

    /// The removals and additions that turn `current` keywords into
    /// `desired` ones. PhotoKit edits keywords one at a time rather than by
    /// assignment. Matching is exact; each list is de-duplicated in
    /// first-seen order.
    static func keywordEdits(current: [String], desired: [String]) -> (remove: [String], add: [String]) {
        let currentSet = Set(current)
        let desiredSet = Set(desired)
        return (
            remove: PhotoService.uniqued(current.filter { !desiredSet.contains($0) }),
            add: PhotoService.uniqued(desired.filter { !currentSet.contains($0) }),
        )
    }

    /// The asset with `id`, refusing an unknown id or an asset whose
    /// properties can't be edited (e.g. one in a shared album).
    private func editableAsset(_ id: String) throws -> PHAsset {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: Self.assetFetchOptions()).firstObject
        else {
            throw PhotoServiceError.notFound("asset(s) \(id)")
        }
        guard asset.canPerform(.properties) else {
            throw PhotoServiceError.operationFailed("asset \(id) does not allow metadata edits")
        }
        return asset
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
                   withLocalIdentifiers: [albumId], options: nil,
               ).firstObject,
               let albumRequest = PHAssetCollectionChangeRequest(for: collection)
            {
                albumRequest.addAssets(placeholders as NSArray)
            }
            let ids = placeholders.map(\.localIdentifier)
            createdIds.withLock { $0 = ids }
        }
        let ids = createdIds.value
        if let shortfall = Self.importShortfall(createdIds: ids, requestedCount: urls.count) {
            throw shortfall
        }
        let fetched = try await assets(ids: ids)
        let byId = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    public func copyAlbum(sourceAlbumId: String, targetAlbumId: String, dryRun: Bool = false) async throws -> PhotoCopyResult {
        try await copyAlbum(
            sourceAlbumId: sourceAlbumId,
            targetAlbumId: targetAlbumId,
            dryRun: dryRun,
            cleanPhantoms: false,
        )
    }

    public func copyAlbum(
        sourceAlbumId: String,
        targetAlbumId: String,
        dryRun: Bool,
        cleanPhantoms: Bool,
    ) async throws -> PhotoCopyResult {
        try await copyAlbum(sourceAlbumId: sourceAlbumId, targetAlbumId: targetAlbumId,
                            dryRun: dryRun, cleanPhantoms: cleanPhantoms, progress: nil)
    }

    public func copyAlbum(
        sourceAlbumId: String,
        targetAlbumId: String,
        dryRun: Bool,
        cleanPhantoms: Bool,
        progress: (@Sendable (PhotoCopyProgress) -> Void)?,
    ) async throws -> PhotoCopyResult {
        try await ensureAuthorized()
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw PhotoServiceError.fullAccessRequired
        }
        guard let source = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [sourceAlbumId], options: nil).firstObject else {
            throw PhotoServiceError.notFound("album \(sourceAlbumId)")
        }
        try ensureAlbumEditable(targetAlbumId, operation: .addContent)
        guard let targetCollection = PHAssetCollection.fetchAssetCollections(
                  withLocalIdentifiers: [targetAlbumId],
                  options: nil,
              ).firstObject,
              targetCollection.assetCollectionType == .album, targetCollection.assetCollectionSubtype == .albumRegular
        else {
            throw PhotoServiceError.invalidInput("targetAlbumId must identify a regular local album")
        }
        guard source.localIdentifier != targetAlbumId else {
            throw PhotoServiceError.invalidInput("sourceAlbumId and targetAlbumId must differ")
        }
        let options = Self.assetFetchOptions()
        let sourceFetch = PHAsset.fetchAssets(in: source, options: options)
        let target = targetCollection
        let targetFetch = PHAsset.fetchAssets(in: target, options: options)
        var targetAssets: [PhotoAsset] = []
        for i in 0 ..< targetFetch.count {
            targetAssets.append(Self.photoAsset(from: targetFetch.object(at: i)))
        }
        var sourceAssets: [PhotoAsset] = []
        var sourceValues: [String: PhotoAsset] = [:]
        var sourceObjects: [String: PHAsset] = [:]
        for i in 0 ..< sourceFetch.count {
            let object = sourceFetch.object(at: i)
            let value = Self.photoAsset(from: object)
            sourceAssets.append(value)
            sourceValues[value.id] = value
            sourceObjects[value.id] = object
        }
        let plan = PhotoService.albumCopyPlan(source: sourceAssets, target: targetAssets,
                                              provenance: provenanceStore.mappings())
        let total = sourceAssets.count
        var result = PhotoCopyResult()
        result.skippedDuplicates = plan.duplicateCount
        result.phantomCloudSharedCount = plan.phantomCloudSharedCount
        if dryRun {
            result.addedByReference = plan.referenceIDs.count
            result.importedAsCopies = plan.copyIDs.count
            progress?(PhotoCopyProgress(total: total, done: total, remaining: 0, failed: 0))
            return result
        }
        progress?(
            PhotoCopyProgress(total: total, done: plan.duplicateCount, remaining: total - plan.duplicateCount, failed: 0),
        )

        if cleanPhantoms, plan.phantomCloudSharedCount > 0 {
            try await performChanges {
                let collections = PHAssetCollection.fetchAssetCollections(
                    withLocalIdentifiers: [targetAlbumId], options: nil,
                )
                guard let collection = collections.firstObject,
                      let changeRequest = PHAssetCollectionChangeRequest(for: collection)
                else { return }
                let phantomFetch = PHAsset.fetchAssets(in: collection, options: Self.assetFetchOptions())
                let phantoms = (0 ..< phantomFetch.count).compactMap { index -> PHAsset? in
                    let asset = phantomFetch.object(at: index)
                    return asset.sourceType.contains(.typeCloudShared) ? asset : nil
                }
                changeRequest.removeAssets(phantoms as NSArray)
            }
        }

        struct StagedResource: Sendable {
            let type: PHAssetResourceType
            let filename: String
            let url: URL
        }
        struct StagedCopy: Sendable {
            let id: String
            let creationDate: Date?
            let latitude: Double?
            let longitude: Double?
            let resources: [StagedResource]
        }
        var pendingReferenceIDs: [String] = []
        var pendingCopies: [StagedCopy] = []
        let tempRoot = URL.temporaryDirectory.appending(path: "PhotosCopy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        func commitBatch() async {
            guard !pendingReferenceIDs.isEmpty || !pendingCopies.isEmpty else { return }
            let referenceIDs = pendingReferenceIDs
            let copies = pendingCopies
            pendingReferenceIDs.removeAll()
            pendingCopies.removeAll()
            do {
                let provenance = Locked<[String: String]>([:])
                try await performChanges {
                    let targetFetch = PHAssetCollection.fetchAssetCollections(
                        withLocalIdentifiers: [targetAlbumId],
                        options: nil,
                    )
                    guard let target = targetFetch.firstObject, let albumRequest = PHAssetCollectionChangeRequest(
                        for: target,
                    ) else { return }
                    if !referenceIDs.isEmpty {
                        let references = PHAsset.fetchAssets(
                            withLocalIdentifiers: referenceIDs,
                            options: Self.assetFetchOptions(),
                        )
                        albumRequest.addAssets(references)
                    }
                    var placeholders: [PHObjectPlaceholder] = []
                    for copy in copies {
                        let request = PHAssetCreationRequest.forAsset()
                        request.creationDate = copy.creationDate
                        if let latitude = copy.latitude, let longitude = copy.longitude {
                            request.location = CLLocation(latitude: latitude, longitude: longitude)
                        }
                        for resource in copy.resources {
                            let resourceOptions = PHAssetResourceCreationOptions()
                            resourceOptions.originalFilename = resource.filename
                            request.addResource(with: resource.type, fileURL: resource.url, options: resourceOptions)
                        }
                        if let placeholder = request.placeholderForCreatedAsset {
                            placeholders.append(placeholder)
                            let localId = placeholder.localIdentifier
                            provenance.withLock { $0[copy.id] = localId }
                        }
                    }
                    albumRequest.addAssets(placeholders as NSArray)
                }
                try provenanceStore.record(provenance.value)
                result.addedByReference += referenceIDs.count
                result.importedAsCopies += copies.count
            } catch {
                for id in referenceIDs + copies.map(\.id) {
                    result.failures.append(PhotoCopyFailure(assetId: id, reason: error.localizedDescription))
                }
            }
            let done = result.addedByReference + result.importedAsCopies + result.skippedDuplicates + result.failures.count
            progress?(
                PhotoCopyProgress(
                    total: total,
                    done: done,
                    remaining: max(0, total - done),
                    failed: result.failures.count,
                ),
            )
        }

        for range in PhotoService.copyBatchRanges(count: plan.referenceIDs.count) {
            pendingReferenceIDs = Array(plan.referenceIDs[range])
            await commitBatch()
        }
        for range in PhotoService.copyBatchRanges(count: plan.copyIDs.count) {
            for id in plan.copyIDs[range] {
                guard let value = sourceValues[id], let asset = sourceObjects[id] else { continue }
                do {
                    let resources = PHAssetResource.assetResources(for: asset)
                    let kinds = resources.map { resource -> PhotoService.CopyResourceKind in
                        switch resource.type {
                        case .photo: .photo
                        case .video: .video
                        case .pairedVideo: .pairedVideo
                        default: .other
                        }
                    }
                    let selected = PhotoService.copyableResourceIndices(kinds).map { resources[$0] }
                    guard !selected.isEmpty else {
                        result.failures.append(
                            PhotoCopyFailure(assetId: id, reason: "no original photo or video resources"),
                        )
                        progress?(
                            PhotoCopyProgress(
                                total: total,
                                done: result.addedByReference + result.importedAsCopies + result.skippedDuplicates + result.failures.count,
                                remaining: max(
                                    0,
                                    total - result.addedByReference - result.importedAsCopies - result.skippedDuplicates - result.failures.count,
                                ),
                                failed: result.failures.count,
                            ),
                        )
                        continue
                    }
                    var staged: [StagedResource] = []
                    for resource in selected {
                        let url = tempRoot.appending(path: UUID().uuidString + "-" + Self.filename(of: resource))
                        let requestOptions = PHAssetResourceRequestOptions()
                        requestOptions.isNetworkAccessAllowed = true
                        try await PHAssetResourceManager.default().writeData(
                            for: resource,
                            toFile: url,
                            options: requestOptions,
                        )
                        staged.append(
                            StagedResource(type: resource.type, filename: Self.filename(of: resource), url: url),
                        )
                    }
                    pendingCopies.append(StagedCopy(id: id, creationDate: value.creationDate,
                                                    latitude: value.latitude, longitude: value.longitude,
                                                    resources: staged))
                } catch {
                    result.failures.append(PhotoCopyFailure(assetId: id, reason: error.localizedDescription))
                    progress?(
                        PhotoCopyProgress(
                            total: total,
                            done: result.addedByReference + result.importedAsCopies + result.skippedDuplicates + result.failures.count,
                            remaining: max(
                                0,
                                total - result.addedByReference - result.importedAsCopies - result.skippedDuplicates - result.failures.count,
                            ),
                            failed: result.failures.count,
                        ),
                    )
                }
            }
            await commitBatch()
        }
        await commitBatch()
        return result
    }

    // MARK: - Existence checks

    /// Throws ``PhotoServiceError/notFound(_:)`` when any id is unknown.
    private func ensureAssetsExist(_ ids: [String]) throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: Self.assetFetchOptions())
        var found = Set<String>()
        for i in 0 ..< fetch.count {
            found.insert(fetch.object(at: i).localIdentifier)
        }
        let missing = Self.missingIDs(requested: ids, found: found)
        guard missing.isEmpty else {
            throw PhotoServiceError.notFound("asset(s) \(missing.joined(separator: ", "))")
        }
    }

    /// The requested ids absent from `found`, each listed once, in input
    /// order. A repeated id that was found is never reported: a PhotoKit
    /// fetch holds each asset once, so callers must compare by identity,
    /// not by count.
    static func missingIDs(requested: [String], found: Set<String>) -> [String] {
        var seen = Set<String>()
        return requested.filter { !found.contains($0) && seen.insert($0).inserted }
    }

    /// The error for an import that created fewer assets than files it was
    /// given, or `nil` when every file was imported. The change block has
    /// already committed the ones that worked, so the message names their
    /// ids for a caller to retry only the rest.
    static func importShortfall(createdIds: [String], requestedCount: Int) -> PhotoServiceError? {
        guard createdIds.count != requestedCount else { return nil }
        let created = createdIds.isEmpty ? "none" : createdIds.joined(separator: ", ")
        return .operationFailed(
            "imported \(createdIds.count) of \(requestedCount) files — unsupported format? created ids: \(created)",
        )
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
