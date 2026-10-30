public import Foundation
import Synchronization

/// Durable mapping from shared source identifiers to the local Photos assets
/// created by `photos_copy_album`. PhotoKit has no custom per-asset metadata
/// field, so this small sidecar is keyed by the asset's PhotoKit identifier.
public final class PhotoCopyProvenanceStore: Sendable {
    private let url: URL
    /// Serializes the read-merge-write cycle on the sidecar file.
    private let fileLock = Mutex(())

    public init(url: URL = PhotoCopyProvenanceStore.defaultURL) { self.url = url }

    public func mappings() -> [String: String] {
        fileLock.withLock { _ in readMappings() }
    }

    public func record(_ values: [String: String]) throws {
        guard !values.isEmpty else { return }
        try fileLock.withLock { _ in
            var all = readMappings()
            all.merge(values) { _, new in new }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try JSONEncoder().encode(all).write(to: url, options: .atomic)
        }
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "PhotosAutomation/copy-provenance.json")
    }

    private func readMappings() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }
}
