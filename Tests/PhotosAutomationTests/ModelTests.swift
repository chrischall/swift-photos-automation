import Foundation
@testable import PhotosAutomation
import Testing

struct ModelTests {
    @Test func `photo asset defaults and identity`() {
        let asset = PhotoAsset(id: "ABC/L0/001")
        #expect(asset.id == "ABC/L0/001")
        #expect(asset.mediaType == .image)
        #expect(asset.isFavorite == false)
        #expect(asset.title == nil)
        #expect(asset.keywords == nil)
    }

    @Test func `photo asset equatable hashable`() {
        let a = PhotoAsset(id: "A")
        let b = PhotoAsset(id: "A")
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
    }

    @Test func `photo album`() {
        let album = PhotoAlbum(id: "alb1", title: "Trips", assetCount: 3)
        #expect(album.id == "alb1")
        #expect(album.title == "Trips")
        #expect(album.assetCount == 3)
    }

    @Test func `search criteria defaults`() {
        let criteria = PhotoSearchCriteria()
        #expect(criteria.startDate == nil)
        #expect(criteria.endDate == nil)
        #expect(criteria.mediaType == nil)
        #expect(criteria.favoritesOnly == false)
        #expect(criteria.albumId == nil)
        #expect(criteria.limit == 50)
    }

    @Test func `media type raw values`() {
        #expect(PhotoMediaType.image.rawValue == "image")
        #expect(PhotoMediaType.video.rawValue == "video")
        #expect(PhotoMediaType.audio.rawValue == "audio")
        #expect(PhotoMediaType.unknown.rawValue == "unknown")
    }
}
