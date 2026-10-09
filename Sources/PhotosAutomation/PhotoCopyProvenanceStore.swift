import Foundation

/// Durable mapping from shared source identifiers to the local Photos assets
/// created by `photos_copy_album`. PhotoKit has no custom per-asset metadata
/// field, so this small sidecar is keyed by the asset's PhotoKit identifier.
public final class PhotoCopyProvenanceStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(url: URL = PhotoCopyProvenanceStore.defaultURL) { self.url = url }

    public func mappings() -> [String: String] {
        lock.withLock {
            guard let data = try? Data(contentsOf: url),
                  let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return values
        }
    }

    public func record(_ values: [String: String]) throws {
        guard !values.isEmpty else { return }
        try lock.withLock {
            var all: [String: String] = [:]
            if let data = try? Data(contentsOf: url) {
                all = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            }
            all.merge(values) { _, new in new }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(all).write(to: url, options: .atomic)
        }
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhotosAutomation", isDirectory: true)
            .appendingPathComponent("copy-provenance.json")
    }
}
