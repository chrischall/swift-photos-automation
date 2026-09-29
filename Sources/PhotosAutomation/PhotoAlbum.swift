import Foundation

/// A user-created album in the Photos library.
public struct PhotoAlbum: Equatable, Hashable, Identifiable, Sendable {
    /// PhotoKit `localIdentifier` of the underlying `PHAssetCollection`.
    public let id: String
    /// The album's display title.
    public let title: String
    /// Number of assets in the album.
    public let assetCount: Int
    public let path: String?
    public let isShared: Bool

    /// Creates an album value.
    public init(id: String, title: String, assetCount: Int, path: String? = nil, isShared: Bool = false) {
        self.id = id
        self.title = title
        self.assetCount = assetCount
        self.path = path
        self.isShared = isShared
    }
}
