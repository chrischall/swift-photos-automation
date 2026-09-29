import Foundation
@testable import PhotosAutomation
import Testing

struct PhotoCopyPlanTests {
    @Test func planSkipsIdsAndPreviouslyImportedCopies() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let target = [
            PhotoAsset(id: "same-id", originalFilename: "IMG_0.HEIC", creationDate: date,
                       pixelWidth: 50, pixelHeight: 40),
            PhotoAsset(id: "local-copy", originalFilename: "IMG_1.HEIC", creationDate: date,
                       pixelWidth: 100, pixelHeight: 80),
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
        #expect(plan.referenceIDs == ["new-library"])
        #expect(plan.copyIDs == ["new-shared"])
    }

    @Test func copyBatchRangesUseTwentyFiveItemBatches() {
        #expect(PhotoService.copyBatchRanges(count: 0).isEmpty)
        #expect(PhotoService.copyBatchRanges(count: 25) == [0 ..< 25])
        #expect(PhotoService.copyBatchRanges(count: 51) == [0 ..< 25, 25 ..< 50, 50 ..< 51])
    }

    @Test func copyableResourceKindsIncludeLivePhotoPairAndVideo() {
        let kinds: [PhotoService.CopyResourceKind] = [.other, .photo, .pairedVideo, .video, .other]
        #expect(PhotoService.copyableResourceIndices(kinds) == [1, 2, 3])
    }
}
