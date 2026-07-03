import Foundation
import Testing
@testable import PhotosAutomation

@Suite struct PhotoServiceOrganizeTests {
    private let store = FakePhotoLibraryStore()
    private var service: PhotoService {
        PhotoService(store: store, runner: FakeAppleScriptRunner())
    }

    // MARK: albums

    @Test func createAlbumPassesTitleThrough() async throws {
        store.createdAlbum = PhotoAlbum(id: "n1", title: "Trip", assetCount: 0)
        let album = try await service.createAlbum(title: "Trip")
        #expect(album == PhotoAlbum(id: "n1", title: "Trip", assetCount: 0))
        #expect(store.calls == ["createAlbum(Trip)"])
    }

    @Test func createAlbumRejectsEmptyTitle() async {
        await #expect(throws: PhotoServiceError.invalidInput("title must not be empty")) {
            _ = try await self.service.createAlbum(title: "")
        }
    }

    @Test func addRejectsEmptyIds() async {
        await #expect(throws: PhotoServiceError.invalidInput("ids must not be empty")) {
            try await self.service.add(ids: [], toAlbum: "alb")
        }
    }

    @Test func addRejectsBlankMember() async {
        await #expect(throws: PhotoServiceError.invalidInput("ids must not contain blank values")) {
            try await self.service.add(ids: ["ok", " "], toAlbum: "alb")
        }
    }

    @Test func addAndRemovePassThrough() async throws {
        try await service.add(ids: ["a"], toAlbum: "alb")
        try await service.remove(ids: ["a"], fromAlbum: "alb")
        #expect(store.calls == [#"add(["a"], toAlbum: alb)"#, #"remove(["a"], fromAlbum: alb)"#])
    }

    // MARK: favorite

    @Test func setFavoritePassesThrough() async throws {
        try await service.setFavorite(id: "a", true)
        #expect(store.calls == ["setFavorite(a, true)"])
    }

    // MARK: export

    @Test func exportPassesThrough() async throws {
        let dir = URL(fileURLWithPath: "/tmp/exports")
        store.exportResult = [dir.appendingPathComponent("IMG_1.HEIC")]
        let urls = try await service.exportOriginals(ids: ["a"], to: dir)
        #expect(urls == [dir.appendingPathComponent("IMG_1.HEIC")])
    }

    @Test func exportRejectsEmptyIds() async {
        await #expect(throws: PhotoServiceError.invalidInput("ids must not be empty")) {
            _ = try await self.service.exportOriginals(ids: [], to: URL(fileURLWithPath: "/tmp"))
        }
    }

    // MARK: imageData

    @Test func imageDataPassesThrough() async throws {
        store.imageDataResult = Data([0xFF, 0xD8])
        let data = try await service.imageData(id: "a", maxDimension: 512)
        #expect(data == Data([0xFF, 0xD8]))
        #expect(store.calls == ["imageData(a, maxDimension: 512)"])
    }

    @Test func imageDataDefaultsTo1024() async throws {
        _ = try await service.imageData(id: "a")
        #expect(store.calls == ["imageData(a, maxDimension: 1024)"])
    }

    @Test func imageDataRejectsNonPositiveDimension() async {
        await #expect(throws: PhotoServiceError.invalidInput("maxDimension must be positive")) {
            _ = try await self.service.imageData(id: "a", maxDimension: 0)
        }
    }

    // MARK: import

    @Test func importRejectsEmptyURLs() async {
        await #expect(throws: PhotoServiceError.invalidInput("urls must not be empty")) {
            _ = try await self.service.importFiles(urls: [])
        }
    }

    @Test func importRejectsMissingFile() async {
        let missing = URL(fileURLWithPath: "/nonexistent/nope.png")
        await #expect(throws: PhotoServiceError.invalidInput("file does not exist: /nonexistent/nope.png")) {
            _ = try await self.service.importFiles(urls: [missing])
        }
    }

    @Test func importPassesThroughForExistingFile() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-automation-test-\(UUID().uuidString).png")
        try Data([0x89, 0x50]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        store.importResult = [PhotoAsset(id: "new1")]
        let imported = try await service.importFiles(urls: [tmp], albumId: "alb")
        #expect(imported == [PhotoAsset(id: "new1")])
        let expected = "importFiles([\"\(tmp.lastPathComponent)\"], toAlbum: alb)"
        #expect(store.calls == [expected])
    }
}
