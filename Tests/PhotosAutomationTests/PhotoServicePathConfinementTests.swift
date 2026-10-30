import Foundation
@testable import PhotosAutomation
import Testing

/// `allowedRoot:` on exportOriginals / importFiles: an opt-in confinement
/// for consumers (e.g. an MCP server) that pass model-chosen paths through.
struct PhotoServicePathConfinementTests {
    private let store = FakePhotoLibraryStore()
    private var service: PhotoService {
        PhotoService(store: store, runner: FakeAppleScriptRunner())
    }

    /// A fresh `<tmp>/confine-<uuid>/root` plus a sibling `outside` dir.
    /// Built from the un-resolved temporary directory (`/var/...` →
    /// `/private/var/...` on macOS) so symlinked prefixes are exercised.
    private func makeSandbox() throws -> (base: URL, root: URL, outside: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("confine-\(UUID().uuidString)")
        let root = base.appendingPathComponent("root")
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        return (base, root, outside)
    }

    private func writePNG(_ url: URL) throws {
        try Data([0x89, 0x50]).write(to: url)
    }

    // MARK: isWithin (pure)

    @Test func `root itself is within`() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        #expect(PhotoService.isWithin(box.root, root: box.root))
    }

    @Test func `not yet created subdirectory is within`() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        #expect(PhotoService.isWithin(box.root.appendingPathComponent("new/deeper"), root: box.root))
    }

    @Test func `resolved and unresolved spellings agree`() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let resolvedRoot = box.root.resolvingSymlinksInPath()
        #expect(PhotoService.isWithin(box.root.appendingPathComponent("x"), root: resolvedRoot))
        #expect(PhotoService.isWithin(resolvedRoot.appendingPathComponent("x"), root: box.root))
    }

    @Test func `sibling directory is outside`() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        #expect(!PhotoService.isWithin(box.outside, root: box.root))
    }

    @Test func `name prefix sibling is outside`() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        // `/…/root-evil` shares a string prefix with `/…/root` but is not inside it.
        #expect(!PhotoService.isWithin(box.base.appendingPathComponent("root-evil"), root: box.root))
    }

    @Test func `dot dot escape is outside`() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let escape = URL(fileURLWithPath: box.root.path + "/../outside")
        #expect(!PhotoService.isWithin(escape, root: box.root))
        let deepEscape = URL(fileURLWithPath: box.root.path + "/nope/../../outside/x")
        #expect(!PhotoService.isWithin(deepEscape, root: box.root))
    }

    @Test func `symlink inside root pointing outside is outside`() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let link = box.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: box.outside)
        #expect(!PhotoService.isWithin(link, root: box.root))
        #expect(!PhotoService.isWithin(link.appendingPathComponent("new"), root: box.root))
    }

    @Test func `dangling symlink inside root is outside`() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        // realpath cannot resolve a link whose target does not exist yet,
        // but mkdir/write through it would still land outside the root.
        let link = box.root.appendingPathComponent("dangling")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: box.outside.appendingPathComponent("not-yet"),
        )
        #expect(!PhotoService.isWithin(link, root: box.root))
        #expect(!PhotoService.isWithin(link.appendingPathComponent("new"), root: box.root))
    }

    // MARK: exportOriginals

    @Test func `export inside root passes through`() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let dir = box.root.appendingPathComponent("exports")
        _ = try await service.exportOriginals(ids: ["a"], to: dir, allowedRoot: box.root)
        #expect(store.calls == [#"exportOriginals(["a"], to: \#(dir.path))"#])
    }

    @Test func `export outside root is refused before touching the library`() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        await #expect(
            throws: PhotoServiceError.invalidInput("directory is outside the allowed root: \(box.outside.path)"),
        ) {
            _ = try await self.service.exportOriginals(ids: ["a"], to: box.outside, allowedRoot: box.root)
        }
        #expect(store.calls.isEmpty)
    }

    @Test func `export without root is unconfined`() async throws {
        _ = try await service.exportOriginals(ids: ["a"], to: URL(fileURLWithPath: "/anywhere"))
        #expect(store.calls == [#"exportOriginals(["a"], to: /anywhere)"#])
    }

    // MARK: importFiles

    @Test func `import inside root passes through`() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let file = box.root.appendingPathComponent("in.png")
        try writePNG(file)
        _ = try await service.importFiles(urls: [file], allowedRoot: box.root)
        #expect(store.calls == [#"importFiles(["in.png"], toAlbum: nil)"#])
    }

    @Test func `import outside root is refused before touching the library`() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let inside = box.root.appendingPathComponent("in.png")
        let outside = box.outside.appendingPathComponent("out.png")
        try writePNG(inside)
        try writePNG(outside)
        await #expect(
            throws: PhotoServiceError.invalidInput("file is outside the allowed root: \(outside.path)"),
        ) {
            _ = try await self.service.importFiles(urls: [inside, outside], allowedRoot: box.root)
        }
        #expect(store.calls.isEmpty)
    }

    @Test func `import refuses outside path before checking it exists`() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        // The confinement error comes first, so a refused caller learns
        // nothing about whether the outside path exists.
        let ghost = box.outside.appendingPathComponent("ghost.png")
        await #expect(
            throws: PhotoServiceError.invalidInput("file is outside the allowed root: \(ghost.path)"),
        ) {
            _ = try await self.service.importFiles(urls: [ghost], allowedRoot: box.root)
        }
    }

    @Test func `import refuses symlink that leaves the root`() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let target = box.outside.appendingPathComponent("secret.png")
        try writePNG(target)
        let link = box.root.appendingPathComponent("looks-local.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        await #expect(
            throws: PhotoServiceError.invalidInput("file is outside the allowed root: \(link.path)"),
        ) {
            _ = try await self.service.importFiles(urls: [link], allowedRoot: box.root)
        }
        #expect(store.calls.isEmpty)
    }
}
