import Foundation
@testable import PhotosAutomation
import Testing

struct PhotoCopyProvenanceStoreTests {
    @Test func `mappings persist and merge across writes`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoCopyProvenance-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = PhotoCopyProvenanceStore(url: url)
        try store.record(["shared-a": "local-a"])
        try store.record(["shared-b": "local-b"])

        #expect(PhotoCopyProvenanceStore(url: url).mappings() == ["shared-a": "local-a", "shared-b": "local-b"])
    }
}

extension PhotoCopyProvenanceStoreTests {
    @Test func `concurrent records are all kept`() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PhotoCopyProvenance-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = PhotoCopyProvenanceStore(url: url)
        try await withThrowingTaskGroup { group in
            for index in 0 ..< 50 {
                group.addTask { try store.record(["shared-\(index)": "local-\(index)"]) }
            }
            try await group.waitForAll()
        }

        #expect(store.mappings().count == 50)
    }

    @Test func `default location is under Application Support`() {
        #expect(PhotoCopyProvenanceStore.defaultURL
            == URL.applicationSupportDirectory.appending(path: "PhotosAutomation/copy-provenance.json"))
    }
}
