import Foundation
@testable import PhotosAutomation
import Testing

struct PhotoCopyProvenanceStoreTests {
    @Test func mappingsPersistAndMergeAcrossWrites() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoCopyProvenance-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = PhotoCopyProvenanceStore(url: url)
        try store.record(["shared-a": "local-a"])
        try store.record(["shared-b": "local-b"])

        #expect(PhotoCopyProvenanceStore(url: url).mappings() == ["shared-a": "local-a", "shared-b": "local-b"])
    }
}
