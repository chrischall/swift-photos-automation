import Foundation

public struct PhotoCopyFailure: Equatable, Sendable {
    public let assetId: String
    public let reason: String
    public init(assetId: String, reason: String) { self.assetId = assetId; self.reason = reason }
}

public struct PhotoCopyResult: Equatable, Sendable {
    public var addedByReference = 0
    public var importedAsCopies = 0
    public var skippedDuplicates = 0
    public var phantomCloudSharedCount = 0
    public var failures: [PhotoCopyFailure] = []
    public init() {}
}

public struct PhotoCopyProgress: Equatable, Sendable {
    public let total: Int
    public let done: Int
    public let remaining: Int
    public let failed: Int
    public init(total: Int, done: Int, remaining: Int, failed: Int) {
        self.total = total; self.done = done; self.remaining = remaining; self.failed = failed
    }
}
