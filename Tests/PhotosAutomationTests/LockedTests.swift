@testable import PhotosAutomation
import Testing

struct LockedTests {
    @Test func `value reads back what was stored`() {
        let box = Locked<[String: String]>([:])
        box.withLock { $0["a"] = "1" }
        #expect(box.value == ["a": "1"])
    }

    @Test func `withLock makes read-modify-write atomic under contention`() async {
        let counter = Locked(0)
        await withTaskGroup { group in
            for _ in 0 ..< 1000 {
                group.addTask { counter.withLock { $0 += 1 } }
            }
        }
        #expect(counter.value == 1000)
    }
}
