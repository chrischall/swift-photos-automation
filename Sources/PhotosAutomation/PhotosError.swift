public import Foundation

/// The single error type thrown by every public ``PhotoService`` method.
///
/// ``PhotoService`` drives two transports, each with its own error type;
/// this enum carries either one unchanged, so a caller handles one typed
/// error and can still tell every failure apart:
///
/// ```swift
/// do {
///     try await service.setTitle(id: id, "Golden hour")
/// } catch {
///     // `error` is a PhotosError — no casting needed.
///     switch error {
///     case let .service(serviceError): …      // validation / PhotoKit
///     case let .appleScript(scriptError): …   // Photos.app over AppleScript
///     case .cancelled: …
///     }
/// }
/// ```
///
/// Its `errorDescription` is the wrapped error's, so logs and
/// `localizedDescription` read exactly as they did before the wrapping.
public enum PhotosError: Error, Equatable, Sendable {
    /// Validation or PhotoKit failure: a bad argument, an unknown asset or
    /// album, missing library access, or an operation PhotoKit refused.
    /// A ``PhotoLibraryStore`` error of any other type arrives here as
    /// ``PhotoServiceError/operationFailed(_:)`` with its description.
    case service(PhotoServiceError)
    /// The AppleScript transport failed — titles and free-text search.
    case appleScript(AppleScriptError)
    /// The underlying store reported Swift task cancellation.
    case cancelled

    /// Normalizes any error to a `PhotosError`: the two transport error
    /// types are wrapped unchanged, `CancellationError` becomes
    /// ``cancelled``, and anything else becomes
    /// ``PhotoServiceError/operationFailed(_:)`` with its
    /// `localizedDescription`.
    public init(_ error: any Error) {
        switch error {
        case let error as PhotosError: self = error
        case let error as PhotoServiceError: self = .service(error)
        case let error as AppleScriptError: self = .appleScript(error)
        case is CancellationError: self = .cancelled
        default: self = .service(.operationFailed(error.localizedDescription))
        }
    }

    /// The wrapped ``PhotoServiceError``, if this is a service failure.
    public var serviceError: PhotoServiceError? {
        if case let .service(error) = self {
            error
        } else {
            nil
        }
    }

    /// The wrapped ``AppleScriptError``, if this is a transport failure.
    public var appleScriptError: AppleScriptError? {
        if case let .appleScript(error) = self {
            error
        } else {
            nil
        }
    }
}

extension PhotosError: LocalizedError {
    /// The wrapped error's description, unchanged.
    public var errorDescription: String? {
        switch self {
        case let .service(error): error.errorDescription
        case let .appleScript(error): error.errorDescription
        case .cancelled: "The Photos operation was cancelled"
        }
    }
}
