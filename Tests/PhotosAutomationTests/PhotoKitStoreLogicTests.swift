import Foundation
@testable import PhotosAutomation
import Testing

/// Pure decision logic extracted from ``PhotoKitStore`` so it is covered
/// without the opt-in PhotoKit integration suite.
struct PhotoKitStoreLogicTests {
    // MARK: missingIDs (ensureAssetsExist / exportOriginals existence check)

    @Test func noMissingIdsWhenAllFound() {
        #expect(PhotoKitStore.missingIDs(requested: ["a", "b"], found: ["a", "b"]).isEmpty)
    }

    @Test func repeatedFoundIdIsNotReportedMissing() {
        // BUG-2: the fetch holds each asset once, so a repeated id must not
        // look like a missing one.
        #expect(PhotoKitStore.missingIDs(requested: ["a", "a", "b"], found: ["a", "b"]).isEmpty)
    }

    @Test func reportsMissingIdsInInputOrder() {
        #expect(PhotoKitStore.missingIDs(requested: ["z", "a", "y"], found: ["a"]) == ["z", "y"])
    }

    @Test func reportsARepeatedMissingIdOnce() {
        #expect(PhotoKitStore.missingIDs(requested: ["x", "a", "x"], found: ["a"]) == ["x"])
    }

    @Test func extraFoundIdsAreIgnored() {
        #expect(PhotoKitStore.missingIDs(requested: ["a"], found: ["a", "other"]).isEmpty)
    }

    // MARK: importShortfall (partial import reporting)

    @Test func noShortfallWhenEveryFileWasCreated() {
        #expect(PhotoKitStore.importShortfall(createdIds: ["n1", "n2"], requestedCount: 2) == nil)
    }

    @Test func partialImportNamesTheCreatedIds() {
        // BUG-3: the change block already committed what worked; the error
        // must name those ids so a caller can retry only the rest.
        #expect(
            PhotoKitStore.importShortfall(createdIds: ["n1"], requestedCount: 3)
                == .operationFailed("imported 1 of 3 files — unsupported format? created ids: n1")
        )
    }

    @Test func totalImportFailureSaysNone() {
        #expect(
            PhotoKitStore.importShortfall(createdIds: [], requestedCount: 2)
                == .operationFailed("imported 0 of 2 files — unsupported format? created ids: none")
        )
    }
}
