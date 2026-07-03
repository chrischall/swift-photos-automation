import Foundation

/// The kind of media a ``PhotoAsset`` holds.
///
/// Raw values are stable lowercase strings so consumers (e.g. MCP tool
/// schemas) can round-trip them without a mapping table.
public enum PhotoMediaType: String, Equatable, Hashable, Sendable, CaseIterable {
    case image
    case video
    case audio
    case unknown
}

/// A single item in the Photos library — photo, video, or audio clip.
///
/// `id` is PhotoKit's `localIdentifier` (e.g. `"4AF382AC-…/L0/001"`),
/// which is the same string Photos' AppleScript dictionary exposes as
/// `media item id` — so one ID works across both transports.
///
/// `title`, `itemDescription`, and `keywords` are only populated by
/// ``PhotoService/asset(id:)``, which reads them via AppleScript —
/// PhotoKit does not expose them. They are `nil` in list/search results.
public struct PhotoAsset: Equatable, Hashable, Identifiable, Sendable {
    /// PhotoKit `localIdentifier` / AppleScript `media item id`.
    public let id: String
    /// Original filename at import time (e.g. `IMG_0042.HEIC`), when known.
    public let originalFilename: String?
    /// When the photo was taken (EXIF capture date), when known.
    public let creationDate: Date?
    /// Kind of media.
    public let mediaType: PhotoMediaType
    /// Whether the user has favorited this asset.
    public let isFavorite: Bool
    /// Pixel width of the asset (0 when unknown).
    public let pixelWidth: Int
    /// Pixel height of the asset (0 when unknown).
    public let pixelHeight: Int
    /// GPS latitude, when the asset has location data.
    public let latitude: Double?
    /// GPS longitude, when the asset has location data.
    public let longitude: Double?
    /// User-assigned title ("name" in Photos). AppleScript-sourced.
    public var title: String?
    /// User-assigned description/caption. AppleScript-sourced.
    public var itemDescription: String?
    /// User-assigned keywords. AppleScript-sourced.
    public var keywords: [String]?

    /// Creates an asset. All metadata parameters default to empty/unknown
    /// so tests and fakes can construct minimal instances.
    public init(
        id: String,
        originalFilename: String? = nil,
        creationDate: Date? = nil,
        mediaType: PhotoMediaType = .image,
        isFavorite: Bool = false,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        latitude: Double? = nil,
        longitude: Double? = nil,
        title: String? = nil,
        itemDescription: String? = nil,
        keywords: [String]? = nil
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.creationDate = creationDate
        self.mediaType = mediaType
        self.isFavorite = isFavorite
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.latitude = latitude
        self.longitude = longitude
        self.title = title
        self.itemDescription = itemDescription
        self.keywords = keywords
    }
}
