import Foundation

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
    ///   - store: PhotoKit access. Defaults to ``PhotoKitStore`` in
    ///     production once Task 9 lands; until then callers pass one in.
    ///   - runner: AppleScript access. Defaults to ``NSAppleScriptRunner``.
    public init(store: PhotoLibraryStore, runner: AppleScriptRunner = NSAppleScriptRunner()) {
        self.store = store
        self.runner = runner
    }

    // MARK: - Reads

    /// All user-created albums.
    public func listAlbums() async throws -> [PhotoAlbum] {
        try await store.listAlbums()
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

    /// Script returning `title<tab>description<tab>kw1,kw2` for one asset.
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
                set AppleScript's text item delimiters to ","
                set kl to kws as text
                set AppleScript's text item delimiters to ""
            end if
            return t & tab & d & tab & kl
        end tell
        """
    }

    /// Parses ``metadataScript(id:)`` output. Empty fields become `nil`;
    /// a malformed line (wrong field count) yields all-`nil` — the caller
    /// treats metadata as best-effort.
    static func parseMetadataLine(_ line: String) -> (title: String?, description: String?, keywords: [String]?) {
        let fields = line.components(separatedBy: "\t")
        guard fields.count == 3 else { return (nil, nil, nil) }
        let title = fields[0].isEmpty ? nil : fields[0]
        let description = fields[1].isEmpty ? nil : fields[1]
        let keywords = fields[2].split(separator: ",").map(String.init)
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

    /// Adds assets to an album.
    public func add(ids: [String], toAlbum albumId: String) async throws {
        try Self.validateIds(ids)
        let albumId = try Self.validateNonEmpty(albumId, name: "albumId")
        try await store.add(ids: ids, toAlbum: albumId)
    }

    /// Removes assets from an album (the assets stay in the library).
    public func remove(ids: [String], fromAlbum albumId: String) async throws {
        try Self.validateIds(ids)
        let albumId = try Self.validateNonEmpty(albumId, name: "albumId")
        try await store.remove(ids: ids, fromAlbum: albumId)
    }

    /// Sets or clears the favorite flag on an asset.
    public func setFavorite(id: String, _ isFavorite: Bool) async throws {
        let id = try Self.validateNonEmpty(id, name: "id")
        try await store.setFavorite(id: id, isFavorite)
    }

    /// Exports each asset's original file (photo or video) into
    /// `directory`, creating the directory if needed.
    /// - Returns: URLs of the written files, in input order.
    public func exportOriginals(ids: [String], to directory: URL) async throws -> [URL] {
        try Self.validateIds(ids)
        return try await store.exportOriginals(ids: ids, to: directory)
    }

    /// A JPEG rendition scaled to fit `maxDimension` pixels on the longest
    /// side — suitable for returning as base64 image content from an MCP
    /// tool without touching disk.
    public func imageData(id: String, maxDimension: Int = 1024) async throws -> Data {
        let id = try Self.validateNonEmpty(id, name: "id")
        guard maxDimension > 0 else {
            throw PhotoServiceError.invalidInput("maxDimension must be positive")
        }
        return try await store.imageData(id: id, maxDimension: maxDimension)
    }

    /// Imports image/video files into the library, optionally adding them
    /// to an album. Every file must exist.
    /// - Returns: The created assets.
    public func importFiles(urls: [URL], albumId: String? = nil) async throws -> [PhotoAsset] {
        guard !urls.isEmpty else {
            throw PhotoServiceError.invalidInput("urls must not be empty")
        }
        for url in urls where !FileManager.default.fileExists(atPath: url.path) {
            throw PhotoServiceError.invalidInput("file does not exist: \(url.path)")
        }
        if let albumId {
            _ = try Self.validateNonEmpty(albumId, name: "albumId")
        }
        return try await store.importFiles(urls: urls, toAlbum: albumId)
    }

    /// Validates an id array: non-empty, no blank members.
    static func validateIds(_ ids: [String]) throws {
        guard !ids.isEmpty else {
            throw PhotoServiceError.invalidInput("ids must not be empty")
        }
        guard ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw PhotoServiceError.invalidInput("ids must not contain blank values")
        }
    }
}
