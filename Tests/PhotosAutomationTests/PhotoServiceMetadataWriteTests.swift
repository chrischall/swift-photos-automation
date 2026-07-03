import Foundation
import Testing
@testable import PhotosAutomation

@Suite struct PhotoServiceMetadataWriteTests {
    private func make(_ runner: FakeAppleScriptRunner = FakeAppleScriptRunner()) -> PhotoService {
        PhotoService(store: FakePhotoLibraryStore(), runner: runner)
    }

    @Test func setTitleGeneratesScript() async throws {
        let runner = FakeAppleScriptRunner()
        try await make(runner).setTitle(id: "A/L0/001", "My \"Best\" Shot")
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].contains(#"set name of media item id "A/L0/001" to "My \"Best\" Shot""#))
    }

    @Test func setTitleRejectsEmptyId() async {
        await #expect(throws: PhotoServiceError.invalidInput("id must not be empty")) {
            try await self.make().setTitle(id: " ", "x")
        }
    }

    @Test func setDescriptionGeneratesScript() async throws {
        let runner = FakeAppleScriptRunner()
        try await make(runner).setDescription(id: "A", "Golden hour")
        #expect(runner.calls[0].contains(#"set description of media item id "A" to "Golden hour""#))
    }

    @Test func setKeywordsGeneratesListLiteral() async throws {
        let runner = FakeAppleScriptRunner()
        try await make(runner).setKeywords(id: "A", ["beach", "sun\"set"])
        #expect(runner.calls[0].contains(#"set keywords of media item id "A" to {"beach", "sun\"set"}"#))
    }

    @Test func setKeywordsEmptyClearsWithEmptyList() async throws {
        let runner = FakeAppleScriptRunner()
        try await make(runner).setKeywords(id: "A", [])
        #expect(runner.calls[0].contains(#"set keywords of media item id "A" to {}"#))
    }

    @Test func appleScriptErrorPropagates() async {
        let runner = FakeAppleScriptRunner()
        runner.queueError("no permission")
        await #expect(throws: AppleScriptError.runtime("no permission")) {
            try await self.make(runner).setTitle(id: "A", "x")
        }
    }
}
