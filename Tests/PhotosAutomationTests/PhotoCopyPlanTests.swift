import Foundation
@testable import PhotosAutomation
import Testing

struct PhotoCopyPlanTests {
    @Test func `plan skips ids and previously imported copies`() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let target = [
            PhotoAsset(id: "same-id", originalFilename: "IMG_0.HEIC", creationDate: date,
                       pixelWidth: 50, pixelHeight: 40),
            PhotoAsset(id: "local-copy", originalFilename: "IMG_1.HEIC", creationDate: date,
                       pixelWidth: 100, pixelHeight: 80),
            PhotoAsset(id: "phantom-shared", originalFilename: "IMG_2.MOV", creationDate: date,
                       mediaType: .video, sourceType: .cloudShared),
        ]
        let source = [
            PhotoAsset(id: "same-id", originalFilename: "IMG_0.HEIC", creationDate: date,
                       pixelWidth: 50, pixelHeight: 40, sourceType: .userLibrary),
            PhotoAsset(id: "duplicate-copy", originalFilename: "IMG_1.HEIC", creationDate: date,
                       pixelWidth: 100, pixelHeight: 80, sourceType: .cloudShared),
            PhotoAsset(id: "new-library", originalFilename: "IMG_3.HEIC", creationDate: date,
                       pixelWidth: 20, pixelHeight: 10, sourceType: .userLibrary),
            PhotoAsset(id: "new-shared", originalFilename: "IMG_2.MOV", creationDate: date,
                       mediaType: .video, sourceType: .cloudShared),
        ]

        let plan = PhotoService.albumCopyPlan(source: source, target: target)

        #expect(plan.duplicateCount == 2)
        #expect(plan.phantomCloudSharedCount == 1)
        #expect(plan.referenceIDs == ["new-library"])
        #expect(plan.copyIDs == ["new-shared"])
    }

    @Test func `cloud shared target members never suppress imports`() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let phantom = PhotoAsset(id: "phantom", originalFilename: "IMG_1.HEIC", creationDate: date,
                                 pixelWidth: 100, pixelHeight: 80, sourceType: .cloudShared)
        let source = PhotoAsset(id: "shared", originalFilename: "IMG_1.HEIC", creationDate: date,
                                pixelWidth: 100, pixelHeight: 80, sourceType: .cloudShared)

        let plan = PhotoService.albumCopyPlan(source: [source], target: [phantom])

        #expect(plan.phantomCloudSharedCount == 1)
        #expect(plan.duplicateCount == 0)
        #expect(plan.copyIDs == ["shared"])
    }

    @Test func `incomplete copy identity does not match unrelated assets`() {
        let source = PhotoAsset(id: "source", sourceType: .cloudShared)
        let target = PhotoAsset(id: "target")

        let plan = PhotoService.albumCopyPlan(source: [source], target: [target])

        #expect(plan.duplicateCount == 0)
        #expect(plan.copyIDs == ["source"])
    }

    @Test func `provenance matches own copy even when filename and dimensions changed`() {
        let source = PhotoAsset(id: "shared-guid", originalFilename: "IMG_1.HEIC", creationDate: Date(),
                                pixelWidth: 4000, pixelHeight: 3000, sourceType: .cloudShared)
        let target = PhotoAsset(id: "local-copy", originalFilename: "IMG_1.jpg", creationDate: Date(),
                                pixelWidth: 2000, pixelHeight: 1500)
        let plan = PhotoService.albumCopyPlan(source: [source], target: [target],
                                              provenance: ["shared-guid": "local-copy"])
        #expect(plan.duplicateCount == 1)
        #expect(plan.copyIDs.isEmpty)
    }

    @Test func `legacy fallback ignores extension and dimensions`() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let source = PhotoAsset(id: "shared", originalFilename: "IMG_1.HEIC", creationDate: date,
                                pixelWidth: 4000, pixelHeight: 3000, sourceType: .cloudShared)
        let target = PhotoAsset(id: "old-copy", originalFilename: "IMG_1.jpg", creationDate: date,
                                pixelWidth: 2000, pixelHeight: 1500)
        let plan = PhotoService.albumCopyPlan(source: [source], target: [target])
        #expect(plan.duplicateCount == 1)
    }

    @Test func `copy batch ranges use twenty five item batches`() {
        #expect(PhotoService.copyBatchRanges(count: 0).isEmpty)
        #expect(PhotoService.copyBatchRanges(count: 25) == [0 ..< 25])
        #expect(PhotoService.copyBatchRanges(count: 51) == [0 ..< 25, 25 ..< 50, 50 ..< 51])
    }

    @Test func `copyable resource kinds include live photo pair and video`() {
        let kinds: [PhotoService.CopyResourceKind] = [.other, .photo, .pairedVideo, .video, .other]
        #expect(PhotoService.copyableResourceIndices(kinds) == [1, 2, 3])
    }
}
