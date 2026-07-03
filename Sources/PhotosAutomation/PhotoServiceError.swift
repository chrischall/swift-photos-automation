import Foundation

/// Domain errors thrown by ``PhotoService`` and ``PhotoLibraryStore``
/// implementations.
///
/// AppleScript transport failures propagate separately as
/// ``AppleScriptError`` — catch both when calling metadata-write or
/// text-search operations.
public enum PhotoServiceError: Error, Equatable, Sendable {
    /// The caller passed an argument that fails validation (empty id,
    /// non-positive limit, missing file). The associated value names the
    /// offending argument.
    case invalidInput(String)
    /// The referenced asset or album does not exist in the library.
    case notFound(String)
    /// Photos library access is not authorized for this process.
    case permissionDenied
    /// PhotoKit reported a failure performing the operation.
    case operationFailed(String)
}

extension PhotoServiceError: LocalizedError {
    /// Human-readable description suitable for logs and user display.
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .notFound(let what):
            return "Not found: \(what)"
        case .permissionDenied:
            return "Photos library access denied — grant access in System Settings → Privacy & Security → Photos"
        case .operationFailed(let message):
            return "Photos operation failed: \(message)"
        }
    }
}
