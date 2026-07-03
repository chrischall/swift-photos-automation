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
}
