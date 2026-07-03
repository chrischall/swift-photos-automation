import Foundation
@testable import PhotosAutomation
import Testing

/// End-to-end tests against the user's real Photos library.
///
/// Requires Photos access for the test binary (macOS prompts on first
/// run) and Automation permission for Photos (for the AppleScript paths).
///
/// **Opt-in**: set `PHOTOS_AUTOMATION_INTEGRATION=1` before `swift test`.
/// Unset, every test here is skipped — keeping CI deterministic and
/// permission-prompt free.
///
/// Cleanup model: **nothing created here is deleted programmatically.**
/// PhotoKit deletion — of assets *and* of albums — always shows a blocking
/// system confirmation dialog, which would hang an unattended run. So the
/// imported 1×1 test PNG and the uniquely-named `PhotosAutomationTests-*`
/// album it creates both stay in the library. Delete them by hand (or
/// leave them — they're harmless). Every other operation the suite performs
/// (import, create album, add/remove members, favorite, title, keywords,
/// export, rendition) is silent, so the suite runs prompt-free once the two
/// TCC grants (Photos access, Automation → Photos) are in place.
@Suite("PhotoService integration", .serialized)
struct PhotoServiceIntegrationTests {
    /// Gate for PhotoKit-only tests — need Photos library access (prompted
    /// on first run) but no Automation permission.
    static let enabledTrait: any TestTrait = .disabled(
        if: ProcessInfo.processInfo.environment["PHOTOS_AUTOMATION_INTEGRATION"] != "1",
        "set PHOTOS_AUTOMATION_INTEGRATION=1 to run against the real Photos library"
    )

    /// Gate for tests that drive Photos.app over AppleScript (metadata
    /// writes, free-text search). These need **Automation → Photos**
    /// permission for the running binary, and `NSAppleScript` targeting
    /// another app is unreliable from inside a `swift test` bundle (it can
    /// hang waiting on the permission prompt, or flake with error -1751 —
    /// the same reentrancy issue swift-notes-automation documented). They
    /// are therefore split behind a *second* opt-in var so the standard
    /// integration pass stays hang-free. The library's AppleScript paths
    /// work correctly from a normal binary (e.g. apple-swift-mcp); this
    /// gate is about the test-bundle environment, not the code.
    static let appleScriptTrait: any TestTrait = .disabled(
        if: ProcessInfo.processInfo.environment["PHOTOS_AUTOMATION_APPLESCRIPT"] != "1",
        "set PHOTOS_AUTOMATION_APPLESCRIPT=1 (plus Automation → Photos permission) to run AppleScript-backed tests"
    )

    /// Album-name prefix for test artifacts. Not used for automated cleanup
    /// (album deletion prompts) — it just makes leftovers easy to find and
    /// remove by hand.
    static let albumPrefix = "PhotosAutomationTests"

    static func makeService() -> PhotoService {
        PhotoService(store: PhotoKitStore(), runner: NSAppleScriptRunner())
    }

    /// Writes a 1×1 PNG to a temp file and returns its URL.
    static func writeTestPNG() throws -> URL {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(albumPrefix)-\(UUID().uuidString).png")
        try Data(base64Encoded: base64)!.write(to: url)
        return url
    }

    @Test("list albums does not throw", Self.enabledTrait)
    func listAlbums() async throws {
        _ = try await Self.makeService().listAlbums()
    }

    @Test("structured search returns limited results", Self.enabledTrait)
    func structuredSearch() async throws {
        let results = try await Self.makeService()
            .search(criteria: PhotoSearchCriteria(limit: 5))
        #expect(results.count <= 5)
        let favorites = try await Self.makeService()
            .search(criteria: PhotoSearchCriteria(favoritesOnly: true, limit: 5))
        // Hoisted out of #expect: the macro can't expand a key-path arg.
        let allFavorited = favorites.allSatisfy(\.isFavorite)
        #expect(allFavorited)
    }

    /// PhotoKit-only end-to-end: import → album → favorite → rendition →
    /// export → remove. Every step here is silent (no confirmation dialog,
    /// no AppleScript), so this runs unattended once Photos access is
    /// granted. Metadata writes and the id-equivalence canary live in
    /// ``metadataRoundTrip()`` (AppleScript-gated).
    @Test("end-to-end (PhotoKit): import, album, favorite, rendition, export", Self.enabledTrait)
    func endToEndPhotoKit() async throws {
        let service = Self.makeService()
        let store = PhotoKitStore()

        // Import a 1×1 PNG. It stays in the library afterward — asset
        // deletion prompts, so we never remove it automatically.
        let png = try Self.writeTestPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let imported = try await service.importFiles(urls: [png])
        try #require(imported.count == 1)
        let assetId = imported[0].id

        // The imported id must be a PhotoKit localIdentifier of the form
        // `UUID/L0/NNN` — the same shape Photos' AppleScript dictionary
        // returns as `media item id`, which is what lets one id drive both
        // transports. (The live AppleScript half is asserted in
        // ``metadataRoundTrip()``.)
        #expect(assetId.contains("/L0/"))

        // Create a uniquely named album and add the asset. The album is
        // left behind (deletion prompts) — its prefix makes it easy to
        // find and remove by hand.
        let albumTitle = "\(Self.albumPrefix)-\(UUID().uuidString.prefix(8))"
        let album = try await service.createAlbum(title: albumTitle)
        try await service.add(ids: [assetId], toAlbum: album.id)
        let inAlbum = try await service.listAssets(albumId: album.id)
        #expect(inAlbum.map(\.id) == [assetId])

        // Favorite round-trip.
        try await service.setFavorite(id: assetId, true)
        let favorited = try await store.asset(id: assetId)
        #expect(favorited?.isFavorite == true)
        try await service.setFavorite(id: assetId, false)

        // In-memory rendition.
        let jpeg = try await service.imageData(id: assetId, maxDimension: 64)
        #expect(!jpeg.isEmpty)

        // Original export.
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.albumPrefix)-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: exportDir) }
        let exported = try await service.exportOriginals(ids: [assetId], to: exportDir)
        try #require(exported.count == 1)
        #expect(FileManager.default.fileExists(atPath: exported[0].path))

        // Remove the asset from the album (silent — removing members
        // doesn't prompt, unlike deleting the album itself).
        try await service.remove(ids: [assetId], fromAlbum: album.id)
        let afterRemove = try await service.listAssets(albumId: album.id)
        #expect(afterRemove.isEmpty)
    }

    /// AppleScript metadata round-trip on a freshly imported asset — the
    /// live proof that a PhotoKit `localIdentifier` also works as an
    /// AppleScript `media item id` (title/keywords written via AppleScript
    /// are read back on the same id). Requires Automation → Photos.
    @Test("metadata round-trip via AppleScript (title, keywords)", Self.enabledTrait, Self.appleScriptTrait)
    func metadataRoundTrip() async throws {
        let service = Self.makeService()
        let png = try Self.writeTestPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let imported = try await service.importFiles(urls: [png])
        try #require(imported.count == 1)
        let assetId = imported[0].id

        // Title round-trip — proves AppleScript reaches the same asset the
        // PhotoKit id names.
        let title = "PhotosAutomation test \(UUID().uuidString.prefix(8))"
        try await service.setTitle(id: assetId, title)
        let hydrated = try await service.asset(id: assetId)
        #expect(hydrated.title == title)

        // Keywords round-trip.
        try await service.setKeywords(id: assetId, ["photosautomation-test"])
        let keyworded = try await service.asset(id: assetId)
        #expect(keyworded.keywords == ["photosautomation-test"])
    }

    @Test("free-text search does not throw", Self.enabledTrait, Self.appleScriptTrait)
    func freeTextSearch() async throws {
        // Fresh imports may not be indexed yet, so assert only that the
        // call succeeds — not that it finds anything.
        _ = try await Self.makeService().searchText("test", limit: 5)
    }
}
