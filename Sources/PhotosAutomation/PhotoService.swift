public import Foundation
import UniformTypeIdentifiers

/// High-level facade over the Photos library.
///
/// Orchestrates two transports:
/// - a ``PhotoLibraryStore`` (PhotoKit) for structured search, metadata,
///   export, import, albums, and favorites;
/// - an ``AppleScriptRunner`` for what PhotoKit cannot do — reading and
///   writing titles, and free-text search.
///
/// The service is a value type with no mutable state: construct once and
/// share freely across concurrent callers.
public struct PhotoService: Sendable {
    private let store: any PhotoLibraryStore
    private let runner: any AppleScriptRunner

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - store: PhotoKit access. Defaults to ``PhotoKitStore``.
    ///   - runner: AppleScript access. Defaults to ``NSAppleScriptRunner``.
    public init(store: any PhotoLibraryStore = PhotoKitStore(), runner: any AppleScriptRunner = NSAppleScriptRunner()) {
        self.store = store
        self.runner = runner
    }

    /// Runs a public operation's body, normalizing whatever it throws —
    /// validation's ``PhotoServiceError``, the runner's
    /// ``AppleScriptError``, or any error from the injected
    /// ``PhotoLibraryStore`` — into the one public ``PhotosError``.
    static func normalizing<T>(_ body: () async throws -> T) async throws(PhotosError) -> T {
        do {
            return try await body()
        } catch {
            throw PhotosError(error)
        }
    }

    // MARK: - Reads

    /// All user-created albums.
    public func listAlbums() async throws(PhotosError) -> [PhotoAlbum] {
        try await Self.normalizing {
            try await store.listAlbums()
        }
    }

    /// Copies an album into a regular local album. Cloud-shared members
    /// already reported in the target are treated as phantom references,
    /// never as duplicates. Set `cleanPhantoms` to remove those memberships
    /// from the target before copying; `dryRun` reports them without edits.
    public func copyAlbum(
        sourceAlbumId: String,
        targetAlbumId: String,
        dryRun: Bool = false,
        cleanPhantoms: Bool = false,
    ) async throws(PhotosError) -> PhotoCopyResult {
        try await copyAlbum(sourceAlbumId: sourceAlbumId, targetAlbumId: targetAlbumId,
                            dryRun: dryRun, cleanPhantoms: cleanPhantoms, progress: nil)
    }

    public func copyAlbum(
        sourceAlbumId: String,
        targetAlbumId: String,
        dryRun: Bool = false,
        cleanPhantoms: Bool = false,
        progress: (@Sendable (PhotoCopyProgress) -> Void)?,
    ) async throws(PhotosError) -> PhotoCopyResult {
        try await Self.normalizing {
            let sourceAlbumId = try Self.validateNonEmpty(sourceAlbumId, name: "sourceAlbumId")
            let targetAlbumId = try Self.validateNonEmpty(targetAlbumId, name: "targetAlbumId")
            return try await store.copyAlbum(
                sourceAlbumId: sourceAlbumId,
                targetAlbumId: targetAlbumId,
                dryRun: dryRun,
                cleanPhantoms: cleanPhantoms,
                progress: progress,
            )
        }
    }

    /// ``copyAlbum(sourceAlbumId:targetAlbumId:dryRun:cleanPhantoms:progress:)``
    /// reporting into a Foundation `Subprogress` instead of a callback, so
    /// the copy can be one part of a caller's larger `ProgressManager` tree.
    ///
    /// The subprogress starts indeterminate; its total becomes the number
    /// of source assets at the first report, and each processed asset
    /// (copied, skipped as a duplicate, or failed) completes one unit.
    /// When the copy throws, the error is the signal: Foundation still
    /// counts the subprogress's share of the parent as done once this call
    /// releases its `ProgressManager`.
    public func copyAlbum(
        sourceAlbumId: String,
        targetAlbumId: String,
        dryRun: Bool = false,
        cleanPhantoms: Bool = false,
        subprogress: consuming Subprogress,
    ) async throws(PhotosError) -> PhotoCopyResult {
        let manager = subprogress.start(totalCount: nil)
        return try await copyAlbum(
            sourceAlbumId: sourceAlbumId, targetAlbumId: targetAlbumId,
            dryRun: dryRun, cleanPhantoms: cleanPhantoms,
        ) { event in
            Self.report(event, to: manager)
        }
    }

    /// Mirrors one callback event onto a `ProgressManager`. An empty copy
    /// (total 0) is reported as one unit of one, so it still finishes.
    static func report(_ event: PhotoCopyProgress, to manager: ProgressManager) {
        manager.setCounts { completed, total in
            if event.total == 0 {
                total = 1
                completed = 1
            } else {
                total = event.total
                completed = min(event.done, event.total)
            }
        }
    }

    struct AlbumCopyPlan: Equatable {
        var referenceIDs: [String] = []
        var copyIDs: [String] = []
        var duplicateCount = 0
        var phantomCloudSharedCount = 0
    }

    /// Plans deduplication and copy mode without PhotoKit objects, so the
    /// decisions can be covered by ordinary unit tests.
    static func albumCopyPlan(source: [PhotoAsset], target: [PhotoAsset], provenance: [String: String] = [:]) -> AlbumCopyPlan {
        let libraryAssets = target.filter { $0.sourceType == .userLibrary }
        let targetIDs = Set(libraryAssets.map(\.id))
        var ids = targetIDs
        var identities = Set(libraryAssets.compactMap(copyIdentity))
        var plan = AlbumCopyPlan(phantomCloudSharedCount: target.count - libraryAssets.count)
        for asset in source {
            let identity = copyIdentity(asset)
            let provenanceMatch = provenance[asset.id].map(targetIDs.contains) ?? false
            guard !ids.contains(asset.id), !provenanceMatch, identity.map({ !identities.contains($0) }) ?? true else {
                plan.duplicateCount += 1
                continue
            }
            if asset.sourceType == .cloudShared {
                plan.copyIDs.append(asset.id)
            } else {
                plan.referenceIDs.append(asset.id)
            }
            ids.insert(asset.id)
            if let identity {
                identities.insert(identity)
            }
        }
        return plan
    }

    /// Stable identity for matching a re-imported copy to its shared source.
    static func copyIdentity(_ asset: PhotoAsset) -> String? {
        guard let filename = asset.originalFilename, let creationDate = asset.creationDate else { return nil }
        let name = URL(filePath: filename).deletingPathExtension().lastPathComponent
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(name)|\(creationDate.timeIntervalSince1970)"
    }

    /// Returns a sequence of index ranges sized for PhotoKit change batches.
    static func copyBatchRanges(count: Int, batchSize: Int = 25) -> [Range<Int>] {
        guard count > 0, batchSize > 0 else { return [] }
        return stride(from: 0, to: count, by: batchSize).map { start in
            start ..< min(start + batchSize, count)
        }
    }

    enum CopyResourceKind: Sendable { case photo, video, pairedVideo, other }

    static func copyableResourceIndices(_ kinds: [CopyResourceKind]) -> [Int] {
        kinds.indices.filter { index in
            switch kinds[index] {
            case .photo, .video, .pairedVideo: true
            case .other: false
            }
        }
    }

    /// Assets in the library (or one album), newest first.
    ///
    /// - Parameters:
    ///   - albumId: Restrict to this album's contents. `nil` = whole library.
    ///   - limit: Maximum results; must be positive.
    public func listAssets(albumId: String? = nil, limit: Int = 50) async throws(PhotosError) -> [PhotoAsset] {
        try await Self.normalizing {
            try Self.validatePositive(limit)
            if let albumId {
                try Self.validateNonEmpty(albumId, name: "albumId")
            }
            return try await store.assets(matching: PhotoSearchCriteria(albumId: albumId, limit: limit))
        }
    }

    /// Assets matching structured criteria (dates, media type, favorites,
    /// album), newest first. For free-text search use ``searchText(_:limit:)``.
    public func search(criteria: PhotoSearchCriteria) async throws(PhotosError) -> [PhotoAsset] {
        try await Self.normalizing {
            try Self.validatePositive(criteria.limit)
            if let albumId = criteria.albumId {
                try Self.validateNonEmpty(albumId, name: "albumId")
            }
            return try await store.assets(matching: criteria)
        }
    }

    /// A single asset with full metadata.
    ///
    /// Everything but the title comes from the store (PhotoKit), including
    /// description, keywords, rating and size. PhotoKit has no title API, so
    /// the title is read over AppleScript, best-effort: if Photos.app is
    /// unreachable or Automation permission is missing it stays `nil` rather
    /// than failing the lookup.
    public func asset(id: String) async throws(PhotosError) -> PhotoAsset {
        try await Self.normalizing {
            let id = try Self.validateNonEmpty(id, name: "id")
            guard var asset = try await store.asset(id: id) else {
                throw PhotoServiceError.notFound("asset \(id)")
            }
            if let title = try? await runner.run(source: Self.titleScript(id: id)) {
                asset.title = title.isEmpty ? nil : title
            }
            return asset
        }
    }

    // MARK: - Validation helpers

    /// Returns the trimmed value, or throws `.invalidInput` when blank.
    @discardableResult
    static func validateNonEmpty(_ value: String, name: String) throws(PhotoServiceError) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PhotoServiceError.invalidInput("\(name) must not be empty")
        }
        return trimmed
    }

    /// Throws `.invalidInput` when `limit` is not positive.
    static func validatePositive(_ limit: Int) throws(PhotoServiceError) {
        guard limit > 0 else {
            throw PhotoServiceError.invalidInput("limit must be positive")
        }
    }

    // MARK: - AppleScript generation & parsing

    /// Escapes a string for interpolation inside a double-quoted
    /// AppleScript string literal. Backslashes first, then quotes.
    static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Script returning one asset's title, or `""` when it has none.
    static func titleScript(id: String) -> String {
        """
        tell application "Photos"
            set t to name of media item id "\(escapeForAppleScript(id))"
            if t is missing value then return ""
            return t
        end tell
        """
    }

    // MARK: - Free-text search

    /// Free-text search via Photos' own search engine (AppleScript
    /// `search for`), which matches titles, keywords, and detected content
    /// — none of which PhotoKit predicates can reach.
    ///
    /// Returned assets preserve Photos' relevance order. IDs that Photos
    /// returns but PhotoKit cannot resolve are silently omitted.
    ///
    /// - Parameters:
    ///   - query: Search text; must not be blank.
    ///   - limit: Maximum results; must be positive.
    public func searchText(_ query: String, limit: Int = 25) async throws(PhotosError) -> [PhotoAsset] {
        try await Self.normalizing {
            let query = try Self.validateNonEmpty(query, name: "query")
            try Self.validatePositive(limit)
            let output = try await runner.run(source: Self.searchScript(query: query, limit: limit))
            let ids = Self.parseIdLines(output)
            guard !ids.isEmpty else { return [] }
            let assets = try await store.assets(ids: ids)
            let byId = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return ids.compactMap { byId[$0] }
        }
    }

    /// Script running Photos' `search for` and returning matched ids,
    /// one per line, capped at `limit`.
    static func searchScript(query: String, limit: Int) -> String {
        let escaped = escapeForAppleScript(query)
        return """
        tell application "Photos"
            set found to search for "\(escaped)"
            set out to ""
            set n to count of found
            if n > \(limit) then set n to \(limit)
            repeat with i from 1 to n
                set out to out & (id of item i of found) & linefeed
            end repeat
            return out
        end tell
        """
    }

    /// Splits script output into trimmed, non-empty id lines.
    static func parseIdLines(_ output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Metadata writes

    /// Sets the asset's title ("name" in Photos). Pass `""` to clear.
    ///
    /// PhotoKit cannot write titles — this goes through Photos.app via
    /// AppleScript, so it requires Automation permission for Photos.
    /// - Throws: ``PhotosError/service(_:)`` wrapping
    ///   ``PhotoServiceError/invalidInput(_:)`` for a blank id;
    ///   ``PhotosError/appleScript(_:)`` when Photos.app rejects the script.
    public func setTitle(id: String, _ title: String) async throws(PhotosError) {
        try await Self.normalizing {
            let id = try Self.validateNonEmpty(id, name: "id")
            _ = try await runner.run(source: Self.setTitleScript(id: id, title: title))
        }
    }

    /// Sets the asset's description/caption. Pass `""` to clear.
    ///
    /// Goes through PhotoKit (no Automation permission needed).
    /// - Throws: ``PhotosError/service(_:)`` for a blank or unknown id, or
    ///   an asset whose metadata can't be edited.
    public func setDescription(id: String, _ description: String) async throws(PhotosError) {
        try await Self.normalizing {
            let id = try Self.validateNonEmpty(id, name: "id")
            try await store.setDescription(id: id, description)
        }
    }

    /// Replaces the asset's keyword list. Pass `[]` to clear.
    ///
    /// Same transport and errors as ``setDescription(id:_:)``.
    public func setKeywords(id: String, _ keywords: [String]) async throws(PhotosError) {
        try await Self.normalizing {
            let id = try Self.validateNonEmpty(id, name: "id")
            try await store.setKeywords(id: id, keywords)
        }
    }

    /// Sets the asset's star rating, 1–5. Pass `0` to clear it.
    ///
    /// Same transport and errors as ``setDescription(id:_:)``, plus
    /// ``PhotosError/service(_:)`` wrapping
    /// ``PhotoServiceError/invalidInput(_:)`` for a rating outside 0–5.
    public func setRating(id: String, _ stars: Int) async throws(PhotosError) {
        try await Self.normalizing {
            let id = try Self.validateNonEmpty(id, name: "id")
            guard (0 ... 5).contains(stars) else {
                throw PhotoServiceError.invalidInput("rating must be 0–5 (0 clears it)")
            }
            try await store.setRating(id: id, stars)
        }
    }

    /// Turns a Live Photo's motion on or off. Off leaves it playing as a
    /// still image; the paired video is kept, so `true` restores it.
    ///
    /// Same transport and errors as ``setDescription(id:_:)``; an asset
    /// that is not a Live Photo is refused.
    public func setLivePhotoPlayback(id: String, enabled: Bool) async throws(PhotosError) {
        try await Self.normalizing {
            let id = try Self.validateNonEmpty(id, name: "id")
            try await store.setLivePhotoPlayback(id: id, enabled: enabled)
        }
    }

    static func setTitleScript(id: String, title: String) -> String {
        """
        tell application "Photos"
            set name of media item id "\(escapeForAppleScript(id))" to "\(escapeForAppleScript(title))"
        end tell
        """
    }

    // MARK: - Organize, export, import

    /// Creates a new top-level album.
    public func createAlbum(title: String) async throws(PhotosError) -> PhotoAlbum {
        try await Self.normalizing {
            let title = try Self.validateNonEmpty(title, name: "title")
            return try await store.createAlbum(title: title)
        }
    }

    /// Adds assets to an album. Repeated ids are collapsed.
    public func add(ids: [String], toAlbum albumId: String) async throws(PhotosError) {
        try await Self.normalizing {
            let ids = try Self.validateIds(ids)
            let albumId = try Self.validateNonEmpty(albumId, name: "albumId")
            try await store.add(ids: Self.uniqued(ids), toAlbum: albumId)
        }
    }

    /// Removes assets from an album (the assets stay in the library).
    /// Repeated ids are collapsed.
    public func remove(ids: [String], fromAlbum albumId: String) async throws(PhotosError) {
        try await Self.normalizing {
            let ids = try Self.validateIds(ids)
            let albumId = try Self.validateNonEmpty(albumId, name: "albumId")
            try await store.remove(ids: Self.uniqued(ids), fromAlbum: albumId)
        }
    }

    /// Sets or clears the favorite flag on an asset.
    public func setFavorite(id: String, _ isFavorite: Bool) async throws(PhotosError) {
        try await Self.normalizing {
            let id = try Self.validateNonEmpty(id, name: "id")
            try await store.setFavorite(id: id, isFavorite)
        }
    }

    /// Exports each asset's original file (photo or video) into
    /// `directory`, creating the directory if needed. All-or-nothing: every
    /// id is checked before anything is written, and if a later write fails
    /// the files this call already wrote are removed.
    ///
    /// > Important: Path trust is the caller's job. Without `allowedRoot`
    /// > the library writes into whatever directory it is given — it does
    /// > no allow-listing. A consumer that forwards untrusted paths (such
    /// > as an MCP tool taking a model-chosen directory) must confine them,
    /// > either with its own policy or by passing `allowedRoot`.
    ///
    /// - Parameters:
    ///   - allowedRoot: When set, `directory` must resolve (symlinks and
    ///     `..` included) to `allowedRoot` or a path beneath it, or the call
    ///     throws ``PhotosError/service(_:)`` wrapping
    ///     ``PhotoServiceError/invalidInput(_:)`` before touching the
    ///     library. The check runs once, up front: it does not guard against
    ///     the filesystem being changed underneath it while the export runs.
    /// - Returns: URLs of the written files, in input order.
    public func exportOriginals(ids: [String], to directory: URL, allowedRoot: URL? = nil) async throws(PhotosError) -> [
        URL
    ] {
        try await Self.normalizing {
            let ids = try Self.validateIds(ids)
            if let allowedRoot, !Self.isWithin(directory, root: allowedRoot) {
                throw PhotoServiceError.invalidInput("directory is outside the allowed root: \(directory.path)")
            }
            return try await store.exportOriginals(ids: ids, to: directory)
        }
    }

    /// A JPEG rendition scaled to fit `maxDimension` pixels on the longest
    /// side — suitable for returning as base64 image content from an MCP
    /// tool without touching disk.
    ///
    /// `maxDimension` is clamped to ``maxRenditionDimension``; the store
    /// further clamps it to the asset's own size, so a rendition is never
    /// upscaled.
    public func imageData(id: String, maxDimension: Int = 1024) async throws(PhotosError) -> Data {
        try await Self.normalizing {
            let id = try Self.validateNonEmpty(id, name: "id")
            guard maxDimension > 0 else {
                throw PhotoServiceError.invalidInput("maxDimension must be positive")
            }
            return try await store.imageData(id: id, maxDimension: min(maxDimension, Self.maxRenditionDimension))
        }
    }

    /// Largest longest-side, in pixels, that ``imageData(id:maxDimension:)``
    /// will render. An unbounded value would make PhotoKit decode (and
    /// upscale to) an arbitrarily large bitmap and exhaust memory.
    public static let maxRenditionDimension = 4096

    /// The longest-side pixel size to request for a rendition: `requested`,
    /// capped at ``maxRenditionDimension`` and at the asset's own longest
    /// side (when known), so it is never upscaled.
    static func renditionDimension(requested: Int, pixelWidth: Int, pixelHeight: Int) -> Int {
        let capped = min(requested, maxRenditionDimension)
        let longest = max(pixelWidth, pixelHeight)
        return longest > 0 ? min(capped, longest) : capped
    }

    /// Imports image/video files into the library, optionally adding them
    /// to an album. Every file must exist, be a regular file, and have an
    /// image or video type — all checked up front, before the library is
    /// touched, so one bad file cannot leave a partial import behind.
    ///
    /// > Important: Path trust is the caller's job. Without `allowedRoot`
    /// > the library reads any file the process can reach — it does no
    /// > allow-listing. A consumer that forwards untrusted paths (such as
    /// > an MCP tool taking model-chosen file paths) must confine them,
    /// > either with its own policy or by passing `allowedRoot`.
    ///
    /// - Parameters:
    ///   - allowedRoot: When set, every url must resolve (symlinks and `..`
    ///     included) to a path beneath `allowedRoot`, or the call throws
    ///     ``PhotosError/service(_:)`` wrapping
    ///     ``PhotoServiceError/invalidInput(_:)`` before any file is
    ///     inspected or the library is touched. The check runs once, up
    ///     front: it does not guard against the filesystem being changed
    ///     underneath it while the import runs.
    /// - Returns: The created assets.
    public func importFiles(urls: [URL], albumId: String? = nil, allowedRoot: URL? = nil) async throws(PhotosError) -> [
        PhotoAsset
    ] {
        try await Self.normalizing {
            guard !urls.isEmpty else {
                throw PhotoServiceError.invalidInput("urls must not be empty")
            }
            if let allowedRoot {
                // Before validateImportable, so a refused path is never stat'd
                // and the error leaks nothing about what exists outside the root.
                for url in urls where !Self.isWithin(url, root: allowedRoot) {
                    throw PhotoServiceError.invalidInput("file is outside the allowed root: \(url.path)")
                }
            }
            for url in urls {
                try Self.validateImportable(url)
            }
            if let albumId {
                _ = try Self.validateNonEmpty(albumId, name: "albumId")
            }
            return try await store.importFiles(urls: urls, toAlbum: albumId)
        }
    }

    /// Whether `url` resolves to `root` or a path beneath it.
    ///
    /// Both sides are canonicalised with ``canonicalComponents(_:)``, so
    /// symlinks (including one inside `root` that points out of it), `..`
    /// segments and alternate spellings like `/tmp` vs `/private/tmp` are
    /// all judged by where the path really lands. Containment is by whole
    /// path component, so `/a/root-evil` is not inside `/a/root`. A path
    /// that cannot be canonicalised is treated as outside.
    static func isWithin(_ url: URL, root: URL) -> Bool {
        guard let rootComponents = canonicalComponents(root),
              let components = canonicalComponents(url)
        else { return false }
        return components.count >= rootComponents.count
            && Array(components.prefix(rootComponents.count)) == rootComponents
    }

    /// The real path of `url` as components, or `nil` when it cannot be
    /// determined. The deepest ancestor that exists is resolved with
    /// `realpath(3)` (the kernel follows every symlink and `..`). The
    /// not-yet-existing tail has its `.` and `..` segments applied
    /// lexically — safe only because it contains no symlinks, so a
    /// dangling symlink (whose target does not exist yet, but which a
    /// later write would follow) yields `nil`.
    static func canonicalComponents(_ url: URL) -> [String]? {
        var existing = url.absoluteURL.path
        var tail: [String] = []
        var resolved: String
        while true {
            // realpath(3) mallocs the result; copy it out, then free it.
            if let real = unsafe realpath(existing, nil) {
                resolved = unsafe String(cString: real)
                unsafe free(real)
                break
            }
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: existing)) != nil {
                return nil
            }
            let parent = (existing as NSString).deletingLastPathComponent
            guard !parent.isEmpty, parent != existing else { return nil }
            tail.insert((existing as NSString).lastPathComponent, at: 0)
            existing = parent
        }
        var components = resolved.split(separator: "/").map(String.init)
        for part in tail where part != "." && part != "/" && !part.isEmpty {
            if part == ".." {
                _ = components.popLast()
            } else {
                components.append(part)
            }
        }
        return components
    }

    /// Validates an id array: non-empty, no blank members.
    /// - Returns: The ids, trimmed.
    static func validateIds(_ ids: [String]) throws(PhotoServiceError) -> [String] {
        guard !ids.isEmpty else {
            throw PhotoServiceError.invalidInput("ids must not be empty")
        }
        let trimmed = ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard trimmed.allSatisfy({ !$0.isEmpty }) else {
            throw PhotoServiceError.invalidInput("ids must not contain blank values")
        }
        return trimmed
    }

    /// Drops repeated ids, keeping the first occurrence's position.
    static func uniqued(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// Throws `.invalidInput` unless `url` is an existing regular file
    /// whose extension maps to an image or video type.
    static func validateImportable(_ url: URL) throws(PhotoServiceError) {
        var isDirectory: ObjCBool = false
        guard unsafe FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw PhotoServiceError.invalidInput("file does not exist: \(url.path)")
        }
        guard !isDirectory.boolValue else {
            throw PhotoServiceError.invalidInput("not a regular file: \(url.path)")
        }
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image) || type.conforms(to: .movie)
        else {
            throw PhotoServiceError.invalidInput("unsupported file type (not an image or video): \(url.path)")
        }
    }
}
