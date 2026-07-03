import Foundation

/// Structured search criteria evaluated by PhotoKit predicates.
///
/// All fields are optional filters; unset fields match everything.
/// For free-text search (titles, keywords, detected content), use
/// ``PhotoService/searchText(_:limit:)`` instead — PhotoKit predicates
/// cannot match on those.
public struct PhotoSearchCriteria: Equatable, Sendable {
    /// Only assets captured on or after this date.
    public var startDate: Date?
    /// Only assets captured on or before this date.
    public var endDate: Date?
    /// Only assets of this media type.
    public var mediaType: PhotoMediaType?
    /// Only favorited assets.
    public var favoritesOnly: Bool
    /// Only assets in the album with this `localIdentifier`.
    public var albumId: String?
    /// Maximum number of results, newest first. Must be positive.
    public var limit: Int

    /// Creates criteria. Defaults match everything, newest 50 first.
    public init(
        startDate: Date? = nil,
        endDate: Date? = nil,
        mediaType: PhotoMediaType? = nil,
        favoritesOnly: Bool = false,
        albumId: String? = nil,
        limit: Int = 50
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.mediaType = mediaType
        self.favoritesOnly = favoritesOnly
        self.albumId = albumId
        self.limit = limit
    }
}
