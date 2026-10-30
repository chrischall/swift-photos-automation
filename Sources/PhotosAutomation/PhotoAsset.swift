public import Foundation

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

/// Where a Photos asset is stored.
public enum PhotoAssetSourceType: String, Equatable, Hashable, Sendable, CaseIterable {
    case userLibrary
    case cloudShared
}

/// A single item in the Photos library — photo, video, or audio clip.
///
/// `id` is PhotoKit's `localIdentifier` (e.g. `"4AF382AC-…/L0/001"`),
/// which is the same string Photos' AppleScript dictionary exposes as
/// `media item id` — so one ID works across both transports.
///
/// `itemDescription`, `keywords`, `rating`, and `fileSize` come from
/// PhotoKit and are filled in everywhere, list and search results included.
/// `title` has no PhotoKit API: only ``PhotoService/asset(id:)`` reads it,
/// over AppleScript, so it is `nil` in list/search results.
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
    public let sourceType: PhotoAssetSourceType
    /// User-assigned title ("name" in Photos). AppleScript-sourced, and
    /// only filled in by ``PhotoService/asset(id:)``.
    public var title: String?
    /// User-assigned description/caption.
    public var itemDescription: String?
    /// User-assigned keywords.
    public var keywords: [String]?
    /// Star rating, 1–5; `nil` when unrated.
    public let rating: Int?
    /// Size in bytes of the primary resource (the original photo or video),
    /// when PhotoKit knows it.
    public let fileSize: Int?

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
        sourceType: PhotoAssetSourceType = .userLibrary,
        title: String? = nil,
        itemDescription: String? = nil,
        keywords: [String]? = nil,
        rating: Int? = nil,
        fileSize: Int? = nil,
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
        self.sourceType = sourceType
        self.title = title
        self.itemDescription = itemDescription
        self.keywords = keywords
        self.rating = rating
        self.fileSize = fileSize
    }
}
