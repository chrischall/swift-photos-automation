import Foundation
@testable import PhotosAutomation
import Testing

struct PhotoServiceMetadataWriteTests {
    private func make(_ runner: FakeAppleScriptRunner = FakeAppleScriptRunner()) -> PhotoService {
        PhotoService(store: FakePhotoLibraryStore(), runner: runner)
    }

    @Test func `set title generates script`() async throws {
        let runner = FakeAppleScriptRunner()
        try await make(runner).setTitle(id: "A/L0/001", "My \"Best\" Shot")
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].contains(#"set name of media item id "A/L0/001" to "My \"Best\" Shot""#))
    }

    @Test func `set title rejects empty id`() async {
        await #expect(throws: PhotosError.service(.invalidInput("id must not be empty"))) {
            try await self.make().setTitle(id: " ", "x")
        }
    }

    @Test func `apple script error propagates`() async {
        let runner = FakeAppleScriptRunner()
        runner.queueError("no permission")
        await #expect(throws: PhotosError.appleScript(.runtime("no permission"))) {
            try await self.make(runner).setTitle(id: "A", "x")
        }
    }
}
