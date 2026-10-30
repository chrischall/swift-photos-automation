import Foundation
@testable import PhotosAutomation
import Testing

/// Pure decision logic extracted from ``PhotoKitStore`` so it is covered
/// without the opt-in PhotoKit integration suite.
struct PhotoKitStoreLogicTests {
    // MARK: missingIDs (ensureAssetsExist / exportOriginals existence check)

    @Test func `no missing ids when all found`() {
        #expect(PhotoKitStore.missingIDs(requested: ["a", "b"], found: ["a", "b"]).isEmpty)
    }

    @Test func `repeated found id is not reported missing`() {
        // BUG-2: the fetch holds each asset once, so a repeated id must not
        // look like a missing one.
        #expect(PhotoKitStore.missingIDs(requested: ["a", "a", "b"], found: ["a", "b"]).isEmpty)
    }

    @Test func `reports missing ids in input order`() {
        #expect(PhotoKitStore.missingIDs(requested: ["z", "a", "y"], found: ["a"]) == ["z", "y"])
    }

    @Test func `reports a repeated missing id once`() {
        #expect(PhotoKitStore.missingIDs(requested: ["x", "a", "x"], found: ["a"]) == ["x"])
    }

    @Test func `extra found ids are ignored`() {
        #expect(PhotoKitStore.missingIDs(requested: ["a"], found: ["a", "other"]).isEmpty)
    }

    // MARK: importShortfall (partial import reporting)

    @Test func `no shortfall when every file was created`() {
        #expect(PhotoKitStore.importShortfall(createdIds: ["n1", "n2"], requestedCount: 2) == nil)
    }

    @Test func `partial import names the created ids`() {
        // BUG-3: the change block already committed what worked; the error
        // must name those ids so a caller can retry only the rest.
        #expect(
            PhotoKitStore.importShortfall(createdIds: ["n1"], requestedCount: 3)
                == .operationFailed("imported 1 of 3 files — unsupported format? created ids: n1"),
        )
    }

    @Test func `total import failure says none`() {
        #expect(
            PhotoKitStore.importShortfall(createdIds: [], requestedCount: 2)
                == .operationFailed("imported 0 of 2 files — unsupported format? created ids: none"),
        )
    }
}
