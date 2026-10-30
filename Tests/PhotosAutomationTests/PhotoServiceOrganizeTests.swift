import Foundation
@testable import PhotosAutomation
import Testing

struct PhotoServiceOrganizeTests {
    private let store = FakePhotoLibraryStore()
    private var service: PhotoService {
        PhotoService(store: store, runner: FakeAppleScriptRunner())
    }

    // MARK: albums

    @Test func `create album passes title through`() async throws {
        store.createdAlbum = PhotoAlbum(id: "n1", title: "Trip", assetCount: 0)
        let album = try await service.createAlbum(title: "Trip")
        #expect(album == PhotoAlbum(id: "n1", title: "Trip", assetCount: 0))
        #expect(store.calls == ["createAlbum(Trip)"])
    }

    @Test func `create album rejects empty title`() async {
        await #expect(throws: PhotosError.service(.invalidInput("title must not be empty"))) {
            _ = try await self.service.createAlbum(title: "")
        }
    }

    @Test func `add rejects empty ids`() async {
        await #expect(throws: PhotosError.service(.invalidInput("ids must not be empty"))) {
            try await self.service.add(ids: [], toAlbum: "alb")
        }
    }

    @Test func `add rejects blank member`() async {
        await #expect(throws: PhotosError.service(.invalidInput("ids must not contain blank values"))) {
            try await self.service.add(ids: ["ok", " "], toAlbum: "alb")
        }
    }

    @Test func `add and remove pass through`() async throws {
        try await service.add(ids: ["a"], toAlbum: "alb")
        try await service.remove(ids: ["a"], fromAlbum: "alb")
        #expect(store.calls == [#"add(["a"], toAlbum: alb)"#, #"remove(["a"], fromAlbum: alb)"#])
    }

    @Test func `add and remove deduplicate ids preserving order`() async throws {
        try await service.add(ids: ["b", "a", "b", "a"], toAlbum: "alb")
        try await service.remove(ids: ["a", "a"], fromAlbum: "alb")
        #expect(store.calls == [#"add(["b", "a"], toAlbum: alb)"#, #"remove(["a"], fromAlbum: alb)"#])
    }

    @Test func `add deduplicates after trimming`() async throws {
        try await service.add(ids: ["a", " a "], toAlbum: "alb")
        #expect(store.calls == [#"add(["a"], toAlbum: alb)"#])
    }

    // MARK: favorite

    @Test func `set favorite passes through`() async throws {
        try await service.setFavorite(id: "a", true)
        #expect(store.calls == ["setFavorite(a, true)"])
    }

    // MARK: export

    @Test func `export passes through`() async throws {
        let dir = URL(fileURLWithPath: "/tmp/exports")
        store.exportResult = [dir.appendingPathComponent("IMG_1.HEIC")]
        let urls = try await service.exportOriginals(ids: ["a"], to: dir)
        #expect(urls == [dir.appendingPathComponent("IMG_1.HEIC")])
    }

    @Test func `export forwards trimmed ids`() async throws {
        let dir = URL(fileURLWithPath: "/tmp/exports")
        _ = try await service.exportOriginals(ids: [" a ", "b\n"], to: dir)
        #expect(store.calls == [#"exportOriginals(["a", "b"], to: /tmp/exports)"#])
    }

    @Test func `export rejects empty ids`() async {
        await #expect(throws: PhotosError.service(.invalidInput("ids must not be empty"))) {
            _ = try await self.service.exportOriginals(ids: [], to: URL(fileURLWithPath: "/tmp"))
        }
    }

    // MARK: imageData

    @Test func `image data passes through`() async throws {
        store.imageDataResult = Data([0xFF, 0xD8])
        let data = try await service.imageData(id: "a", maxDimension: 512)
        #expect(data == Data([0xFF, 0xD8]))
        #expect(store.calls == ["imageData(a, maxDimension: 512)"])
    }

    @Test func `image data defaults to 1024`() async throws {
        _ = try await service.imageData(id: "a")
        #expect(store.calls == ["imageData(a, maxDimension: 1024)"])
    }

    @Test func `image data rejects non positive dimension`() async {
        await #expect(throws: PhotosError.service(.invalidInput("maxDimension must be positive"))) {
            _ = try await self.service.imageData(id: "a", maxDimension: 0)
        }
    }

    @Test func `image data clamps oversized dimension to cap`() async throws {
        _ = try await service.imageData(id: "a", maxDimension: 50000)
        #expect(store.calls == ["imageData(a, maxDimension: \(PhotoService.maxRenditionDimension))"])
    }

    @Test func `rendition cap is sane`() {
        #expect(PhotoService.maxRenditionDimension == 4096)
    }

    @Test(arguments: [
        // requested, pixelWidth, pixelHeight, expected
        (512, 4000, 3000, 512), // smaller than the asset: honoured
        (50000, 8000, 6000, 4096), // above the cap: clamped to the cap
        (4096, 1200, 900, 1200), // larger than the asset: never upscale
        (2000, 900, 1600, 1600), // portrait: longest side is the height
        (800, 0, 0, 800), // unknown pixel size: cap only
    ])
    func `rendition dimension clamps`(requested: Int, width: Int, height: Int, expected: Int) {
        #expect(
            PhotoService.renditionDimension(requested: requested, pixelWidth: width, pixelHeight: height) == expected,
        )
    }

    // MARK: import

    @Test func `import rejects empty URLs`() async {
        await #expect(throws: PhotosError.service(.invalidInput("urls must not be empty"))) {
            _ = try await self.service.importFiles(urls: [])
        }
    }

    @Test func `import rejects missing file`() async {
        let missing = URL(fileURLWithPath: "/nonexistent/nope.png")
        await #expect(throws: PhotosError.service(.invalidInput("file does not exist: /nonexistent/nope.png"))) {
            _ = try await self.service.importFiles(urls: [missing])
        }
    }

    @Test func `import rejects directory before touching the library`() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-automation-dir-\(UUID().uuidString).png")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        await #expect(throws: PhotosError.service(.invalidInput("not a regular file: \(dir.path)"))) {
            _ = try await self.service.importFiles(urls: [dir])
        }
        #expect(store.calls.isEmpty)
    }

    @Test func `import rejects unsupported type before touching the library`() async throws {
        let good = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-automation-test-\(UUID().uuidString).png")
        let bad = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-automation-test-\(UUID().uuidString).txt")
        try Data([0x89, 0x50]).write(to: good)
        try Data("hi".utf8).write(to: bad)
        defer {
            try? FileManager.default.removeItem(at: good)
            try? FileManager.default.removeItem(at: bad)
        }
        await #expect(
            throws: PhotosError.service(.invalidInput("unsupported file type (not an image or video): \(bad.path)")),
        ) {
            _ = try await self.service.importFiles(urls: [good, bad])
        }
        #expect(store.calls.isEmpty)
    }

    @Test func `import accepts video`() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-automation-test-\(UUID().uuidString).mov")
        try Data([0x00]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await service.importFiles(urls: [tmp])
        #expect(store.calls.count == 1)
    }

    @Test func `import passes through for existing file`() async throws {
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

struct AvailableURLTests {
    @Test func `dedupes existing filenames`() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-automation-dedupe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = PhotoKitStore.availableURL(in: dir, filename: "IMG_1.HEIC")
        #expect(first.lastPathComponent == "IMG_1.HEIC")
        try Data().write(to: first)

        let second = PhotoKitStore.availableURL(in: dir, filename: "IMG_1.HEIC")
        #expect(second.lastPathComponent == "IMG_1 (1).HEIC")
    }
}

struct WriteAllOrNothingTests {
    private struct Boom: Error {}

    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-automation-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func `returns every written URL in order`() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try await PhotoKitStore.writeAllOrNothing(["a", "b"]) { name in
            let url = dir.appendingPathComponent(name)
            try Data([1]).write(to: url)
            return url
        }
        #expect(urls.map(\.lastPathComponent) == ["a", "b"])
    }

    @Test func `removes earlier files when a later write fails`() async throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([9]).write(to: dir.appendingPathComponent("preexisting"))

        await #expect(throws: Boom.self) {
            _ = try await PhotoKitStore.writeAllOrNothing(["a", "b", "c"]) { name in
                if name == "c" {
                    throw Boom()
                }
                let url = dir.appendingPathComponent(name)
                try Data([1]).write(to: url)
                return url
            }
        }
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        // Files from this call are gone; files that were already there stay.
        #expect(left == ["preexisting"])
    }
}

struct ResourceFilenameTests {
    /// `PHAssetResource.filename` (macOS 27) is optional where the deprecated
    /// `originalFilename` was not; a nameless resource still needs a file name
    /// with the right extension for export and album-copy staging.
    @Test(arguments: [
        ("public.heic", "resource.heic"),
        ("public.jpeg", "resource.jpeg"),
        ("com.apple.quicktime-movie", "resource.mov"),
    ])
    func `a nameless resource is named from its type`(uti: String, expected: String) {
        #expect(PhotoKitStore.fallbackFilename(uniformTypeIdentifier: uti) == expected)
    }

    @Test func `an unknown type still gets a usable name`() {
        #expect(PhotoKitStore.fallbackFilename(uniformTypeIdentifier: "com.example.unknown-nope") == "resource")
    }
}
