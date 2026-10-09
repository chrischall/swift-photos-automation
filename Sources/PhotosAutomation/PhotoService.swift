import Foundation
import UniformTypeIdentifiers

/// High-level facade over the Photos library.
///
/// Orchestrates two transports:
/// - a ``PhotoLibraryStore`` (PhotoKit) for structured search, metadata,
///   export, import, albums, and favorites;
/// - an ``AppleScriptRunner`` for what PhotoKit cannot do — reading and
///   writing titles/descriptions/keywords, and free-text search.
///
/// The service is a value type with no mutable state: construct once and
/// share freely across concurrent callers.
public struct PhotoService: Sendable {
    private let store: PhotoLibraryStore
    private let runner: AppleScriptRunner

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - store: PhotoKit access. Defaults to ``PhotoKitStore``.
    ///   - runner: AppleScript access. Defaults to ``NSAppleScriptRunner``.
    public init(store: PhotoLibraryStore = PhotoKitStore(), runner: AppleScriptRunner = NSAppleScriptRunner()) {
        self.store = store
        self.runner = runner
    }

    // MARK: - Reads

    /// All user-created albums.
    public func listAlbums() async throws -> [PhotoAlbum] {
        try await store.listAlbums()
    }

    /// Copies an album into a regular local album. Cloud-shared members
    /// already reported in the target are treated as phantom references,
    /// never as duplicates. Set `cleanPhantoms` to remove those memberships
    /// from the target before copying; `dryRun` reports them without edits.
    public func copyAlbum(
        sourceAlbumId: String,
        targetAlbumId: String,
        dryRun: Bool = false,
        cleanPhantoms: Bool = false
    ) async throws -> PhotoCopyResult {
        try await copyAlbum(sourceAlbumId: sourceAlbumId, targetAlbumId: targetAlbumId,
                            dryRun: dryRun, cleanPhantoms: cleanPhantoms, progress: nil)
    }

    public func copyAlbum(
        sourceAlbumId: String,
        targetAlbumId: String,
        dryRun: Bool = false,
        cleanPhantoms: Bool = false,
        progress: (@Sendable (PhotoCopyProgress) -> Void)?
    ) async throws -> PhotoCopyResult {
        let sourceAlbumId = try Self.validateNonEmpty(sourceAlbumId, name: "sourceAlbumId")
        let targetAlbumId = try Self.validateNonEmpty(targetAlbumId, name: "targetAlbumId")
        return try await store.copyAlbum(
            sourceAlbumId: sourceAlbumId,
            targetAlbumId: targetAlbumId,
            dryRun: dryRun,
            cleanPhantoms: cleanPhantoms,
            progress: progress
        )
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
            if asset.sourceType == .cloudShared { plan.copyIDs.append(asset.id) }
            else { plan.referenceIDs.append(asset.id) }
            ids.insert(asset.id)
            if let identity { identities.insert(identity) }
        }
        return plan
    }

    /// Stable identity for matching a re-imported copy to its shared source.
    static func copyIdentity(_ asset: PhotoAsset) -> String? {
        guard let filename = asset.originalFilename, let creationDate = asset.creationDate else { return nil }
        let name = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
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
    public func listAssets(albumId: String? = nil, limit: Int = 50) async throws -> [PhotoAsset] {
        try Self.validatePositive(limit)
        if let albumId {
            try Self.validateNonEmpty(albumId, name: "albumId")
        }
        return try await store.assets(matching: PhotoSearchCriteria(albumId: albumId, limit: limit))
    }

    /// Assets matching structured criteria (dates, media type, favorites,
    /// album), newest first. For free-text search use ``searchText(_:limit:)``.
    public func search(criteria: PhotoSearchCriteria) async throws -> [PhotoAsset] {
        try Self.validatePositive(criteria.limit)
        if let albumId = criteria.albumId {
            try Self.validateNonEmpty(albumId, name: "albumId")
        }
        return try await store.assets(matching: criteria)
    }

    /// A single asset with full metadata.
    ///
    /// PhotoKit fields come from the store; `title`, `itemDescription`,
    /// and `keywords` are hydrated via AppleScript. Hydration is
    /// best-effort: if Photos.app is unreachable or Automation permission
    /// is missing, those three fields stay `nil` rather than failing the
    /// whole lookup.
    public func asset(id: String) async throws -> PhotoAsset {
        let id = try Self.validateNonEmpty(id, name: "id")
        guard var asset = try await store.asset(id: id) else {
            throw PhotoServiceError.notFound("asset \(id)")
        }
        if let line = try? await runner.run(source: Self.metadataScript(id: id)) {
            let meta = Self.parseMetadataLine(line)
            asset.title = meta.title
            asset.itemDescription = meta.description
            asset.keywords = meta.keywords
        }
        return asset
    }

    // MARK: - Validation helpers

    /// Returns the trimmed value, or throws `.invalidInput` when blank.
    @discardableResult
    static func validateNonEmpty(_ value: String, name: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PhotoServiceError.invalidInput("\(name) must not be empty")
        }
        return trimmed
    }

    /// Throws `.invalidInput` when `limit` is not positive.
    static func validatePositive(_ limit: Int) throws {
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

    /// Field separator in ``metadataScript(id:)`` output: ASCII 30
    /// (record separator). Control characters cannot come from normal
    /// user input, unlike the tab or comma a title, description, or
    /// keyword may legitimately contain.
    static let metadataFieldSeparator = "\u{1E}"

    /// Keyword separator in ``metadataScript(id:)`` output: ASCII 31
    /// (unit separator).
    static let metadataKeywordSeparator = "\u{1F}"

    /// Script returning `title<RS>description<RS>kw1<US>kw2` for one asset,
    /// where RS/US are ``metadataFieldSeparator`` and
    /// ``metadataKeywordSeparator``.
    ///
    /// `missing value` fields are coerced to `""` inside the script so the
    /// Swift-side parser can rely on a clean three-field line.
    static func metadataScript(id: String) -> String {
        let escaped = escapeForAppleScript(id)
        return """
        tell application "Photos"
            set m to media item id "\(escaped)"
            set t to name of m
            if t is missing value then set t to ""
            set d to description of m
            if d is missing value then set d to ""
            set kl to ""
            set kws to keywords of m
            if kws is not missing value then
                set AppleScript's text item delimiters to (character id 31)
                set kl to kws as text
                set AppleScript's text item delimiters to ""
            end if
            return t & (character id 30) & d & (character id 30) & kl
        end tell
        """
    }

    /// Parses ``metadataScript(id:)`` output. Empty fields become `nil`;
    /// a malformed line (wrong field count) yields all-`nil` — the caller
    /// treats metadata as best-effort.
    static func parseMetadataLine(_ line: String) -> (title: String?, description: String?, keywords: [String]?) {
        let fields = line.components(separatedBy: metadataFieldSeparator)
        guard fields.count == 3 else { return (nil, nil, nil) }
        let title = fields[0].isEmpty ? nil : fields[0]
        let description = fields[1].isEmpty ? nil : fields[1]
        let keywords = fields[2].components(separatedBy: metadataKeywordSeparator).filter { !$0.isEmpty }
        return (title, description, keywords.isEmpty ? nil : keywords)
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
    public func searchText(_ query: String, limit: Int = 25) async throws -> [PhotoAsset] {
        let query = try Self.validateNonEmpty(query, name: "query")
        try Self.validatePositive(limit)
        let output = try await runner.run(source: Self.searchScript(query: query, limit: limit))
        let ids = Self.parseIdLines(output)
        guard !ids.isEmpty else { return [] }
        let assets = try await store.assets(ids: ids)
        let byId = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
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

    // MARK: - Metadata writes (AppleScript)

    /// Sets the asset's title ("name" in Photos). Pass `""` to clear.
    ///
    /// PhotoKit cannot write titles — this goes through Photos.app via
    /// AppleScript, so it requires Automation permission for Photos.
    /// - Throws: ``PhotoServiceError/invalidInput(_:)`` for a blank id;
    ///   ``AppleScriptError`` when Photos.app rejects the script.
    public func setTitle(id: String, _ title: String) async throws {
        let id = try Self.validateNonEmpty(id, name: "id")
        _ = try await runner.run(source: Self.setTitleScript(id: id, title: title))
    }

    /// Sets the asset's description/caption. Pass `""` to clear.
    ///
    /// Same transport and error behavior as ``setTitle(id:_:)``.
    public func setDescription(id: String, _ description: String) async throws {
        let id = try Self.validateNonEmpty(id, name: "id")
        _ = try await runner.run(source: Self.setDescriptionScript(id: id, description: description))
    }

    /// Replaces the asset's keyword list. Pass `[]` to clear.
    ///
    /// Same transport and error behavior as ``setTitle(id:_:)``.
    public func setKeywords(id: String, _ keywords: [String]) async throws {
        let id = try Self.validateNonEmpty(id, name: "id")
        _ = try await runner.run(source: Self.setKeywordsScript(id: id, keywords: keywords))
    }

    static func setTitleScript(id: String, title: String) -> String {
        """
        tell application "Photos"
            set name of media item id "\(escapeForAppleScript(id))" to "\(escapeForAppleScript(title))"
        end tell
        """
    }

    static func setDescriptionScript(id: String, description: String) -> String {
        """
        tell application "Photos"
            set description of media item id "\(escapeForAppleScript(id))" to "\(escapeForAppleScript(description))"
        end tell
        """
    }

    static func setKeywordsScript(id: String, keywords: [String]) -> String {
        let list = keywords.map { "\"\(escapeForAppleScript($0))\"" }.joined(separator: ", ")
        return """
        tell application "Photos"
            set keywords of media item id "\(escapeForAppleScript(id))" to {\(list)}
        end tell
        """
    }

    // MARK: - Organize, export, import

    /// Creates a new top-level album.
    public func createAlbum(title: String) async throws -> PhotoAlbum {
        let title = try Self.validateNonEmpty(title, name: "title")
        return try await store.createAlbum(title: title)
    }

    /// Adds assets to an album. Repeated ids are collapsed.
    public func add(ids: [String], toAlbum albumId: String) async throws {
        let ids = try Self.validateIds(ids)
        let albumId = try Self.validateNonEmpty(albumId, name: "albumId")
        try await store.add(ids: Self.uniqued(ids), toAlbum: albumId)
    }

    /// Removes assets from an album (the assets stay in the library).
    /// Repeated ids are collapsed.
    public func remove(ids: [String], fromAlbum albumId: String) async throws {
        let ids = try Self.validateIds(ids)
        let albumId = try Self.validateNonEmpty(albumId, name: "albumId")
        try await store.remove(ids: Self.uniqued(ids), fromAlbum: albumId)
    }

    /// Sets or clears the favorite flag on an asset.
    public func setFavorite(id: String, _ isFavorite: Bool) async throws {
        let id = try Self.validateNonEmpty(id, name: "id")
        try await store.setFavorite(id: id, isFavorite)
    }

    /// Exports each asset's original file (photo or video) into
    /// `directory`, creating the directory if needed. All-or-nothing: every
    /// id is checked before anything is written, and if a later write fails
    /// the files this call already wrote are removed.
    /// - Returns: URLs of the written files, in input order.
    public func exportOriginals(ids: [String], to directory: URL) async throws -> [URL] {
        let ids = try Self.validateIds(ids)
        return try await store.exportOriginals(ids: ids, to: directory)
    }

    /// A JPEG rendition scaled to fit `maxDimension` pixels on the longest
    /// side — suitable for returning as base64 image content from an MCP
    /// tool without touching disk.
    ///
    /// `maxDimension` is clamped to ``maxRenditionDimension``; the store
    /// further clamps it to the asset's own size, so a rendition is never
    /// upscaled.
    public func imageData(id: String, maxDimension: Int = 1024) async throws -> Data {
        let id = try Self.validateNonEmpty(id, name: "id")
        guard maxDimension > 0 else {
            throw PhotoServiceError.invalidInput("maxDimension must be positive")
        }
        return try await store.imageData(id: id, maxDimension: min(maxDimension, Self.maxRenditionDimension))
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
    /// - Returns: The created assets.
    public func importFiles(urls: [URL], albumId: String? = nil) async throws -> [PhotoAsset] {
        guard !urls.isEmpty else {
            throw PhotoServiceError.invalidInput("urls must not be empty")
        }
        for url in urls {
            try Self.validateImportable(url)
        }
        if let albumId {
            _ = try Self.validateNonEmpty(albumId, name: "albumId")
        }
        return try await store.importFiles(urls: urls, toAlbum: albumId)
    }

    /// Validates an id array: non-empty, no blank members.
    /// - Returns: The ids, trimmed.
    static func validateIds(_ ids: [String]) throws -> [String] {
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
    static func validateImportable(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
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
