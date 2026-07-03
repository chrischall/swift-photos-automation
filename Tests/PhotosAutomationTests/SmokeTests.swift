import Testing
@testable import PhotosAutomation

@Suite struct SmokeTests {
    @Test func packageBuilds() {
        #expect(Bool(true))
    }
}
