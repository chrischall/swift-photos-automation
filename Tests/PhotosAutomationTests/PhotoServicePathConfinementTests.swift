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

    @Test func rootItselfIsWithin() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        #expect(PhotoService.isWithin(box.root, root: box.root))
    }

    @Test func notYetCreatedSubdirectoryIsWithin() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        #expect(PhotoService.isWithin(box.root.appendingPathComponent("new/deeper"), root: box.root))
    }

    @Test func resolvedAndUnresolvedSpellingsAgree() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let resolvedRoot = box.root.resolvingSymlinksInPath()
        #expect(PhotoService.isWithin(box.root.appendingPathComponent("x"), root: resolvedRoot))
        #expect(PhotoService.isWithin(resolvedRoot.appendingPathComponent("x"), root: box.root))
    }

    @Test func siblingDirectoryIsOutside() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        #expect(!PhotoService.isWithin(box.outside, root: box.root))
    }

    @Test func namePrefixSiblingIsOutside() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        // `/…/root-evil` shares a string prefix with `/…/root` but is not inside it.
        #expect(!PhotoService.isWithin(box.base.appendingPathComponent("root-evil"), root: box.root))
    }

    @Test func dotDotEscapeIsOutside() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let escape = URL(fileURLWithPath: box.root.path + "/../outside")
        #expect(!PhotoService.isWithin(escape, root: box.root))
        let deepEscape = URL(fileURLWithPath: box.root.path + "/nope/../../outside/x")
        #expect(!PhotoService.isWithin(deepEscape, root: box.root))
    }

    @Test func symlinkInsideRootPointingOutsideIsOutside() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let link = box.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: box.outside)
        #expect(!PhotoService.isWithin(link, root: box.root))
        #expect(!PhotoService.isWithin(link.appendingPathComponent("new"), root: box.root))
    }

    @Test func danglingSymlinkInsideRootIsOutside() throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        // realpath cannot resolve a link whose target does not exist yet,
        // but mkdir/write through it would still land outside the root.
        let link = box.root.appendingPathComponent("dangling")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: box.outside.appendingPathComponent("not-yet")
        )
        #expect(!PhotoService.isWithin(link, root: box.root))
        #expect(!PhotoService.isWithin(link.appendingPathComponent("new"), root: box.root))
    }

    // MARK: exportOriginals

    @Test func exportInsideRootPassesThrough() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let dir = box.root.appendingPathComponent("exports")
        _ = try await service.exportOriginals(ids: ["a"], to: dir, allowedRoot: box.root)
        #expect(store.calls == [#"exportOriginals(["a"], to: \#(dir.path))"#])
    }

    @Test func exportOutsideRootIsRefusedBeforeTouchingTheLibrary() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        await #expect(
            throws: PhotoServiceError.invalidInput("directory is outside the allowed root: \(box.outside.path)")
        ) {
            _ = try await self.service.exportOriginals(ids: ["a"], to: box.outside, allowedRoot: box.root)
        }
        #expect(store.calls.isEmpty)
    }

    @Test func exportWithoutRootIsUnconfined() async throws {
        _ = try await service.exportOriginals(ids: ["a"], to: URL(fileURLWithPath: "/anywhere"))
        #expect(store.calls == [#"exportOriginals(["a"], to: /anywhere)"#])
    }

    // MARK: importFiles

    @Test func importInsideRootPassesThrough() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let file = box.root.appendingPathComponent("in.png")
        try writePNG(file)
        _ = try await service.importFiles(urls: [file], allowedRoot: box.root)
        #expect(store.calls == [#"importFiles(["in.png"], toAlbum: nil)"#])
    }

    @Test func importOutsideRootIsRefusedBeforeTouchingTheLibrary() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let inside = box.root.appendingPathComponent("in.png")
        let outside = box.outside.appendingPathComponent("out.png")
        try writePNG(inside)
        try writePNG(outside)
        await #expect(
            throws: PhotoServiceError.invalidInput("file is outside the allowed root: \(outside.path)")
        ) {
            _ = try await self.service.importFiles(urls: [inside, outside], allowedRoot: box.root)
        }
        #expect(store.calls.isEmpty)
    }

    @Test func importRefusesOutsidePathBeforeCheckingItExists() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        // The confinement error comes first, so a refused caller learns
        // nothing about whether the outside path exists.
        let ghost = box.outside.appendingPathComponent("ghost.png")
        await #expect(
            throws: PhotoServiceError.invalidInput("file is outside the allowed root: \(ghost.path)")
        ) {
            _ = try await self.service.importFiles(urls: [ghost], allowedRoot: box.root)
        }
    }

    @Test func importRefusesSymlinkThatLeavesTheRoot() async throws {
        let box = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: box.base) }
        let target = box.outside.appendingPathComponent("secret.png")
        try writePNG(target)
        let link = box.root.appendingPathComponent("looks-local.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        await #expect(
            throws: PhotoServiceError.invalidInput("file is outside the allowed root: \(link.path)")
        ) {
            _ = try await self.service.importFiles(urls: [link], allowedRoot: box.root)
        }
        #expect(store.calls.isEmpty)
    }
}
