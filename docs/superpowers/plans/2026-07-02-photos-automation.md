# swift-photos-automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Swift 6 library (`PhotosAutomation`) that reads, searches, exports, organizes, and imports Apple Photos content via a hybrid PhotoKit + AppleScript design, for consumption by the `apple-swift-mcp` server.

**Architecture:** A `Sendable` `PhotoService` struct orchestrates two injected transports: a `PhotoLibraryStore` protocol (concrete `PhotoKitStore` wrapping PhotoKit) for structured search/metadata/export/import/albums/favorites, and an `AppleScriptRunner` protocol (concrete `NSAppleScriptRunner`, copied verbatim from swift-notes-automation) for the two things PhotoKit cannot do — writing titles/descriptions/keywords and free-text search. Photos' AppleScript `media item id` equals PhotoKit's `localIdentifier`, so one ID works across both transports (verified by integration test).

**Tech Stack:** Swift 6 (`swift-tools-version: 6.0`), macOS 14+, PhotoKit (`Photos` framework), `NSAppleScript`, Swift Testing. Zero external SPM dependencies.

**Spec:** `docs/superpowers/specs/2026-07-02-photos-automation-design.md`

## Global Constraints

- `swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, strict concurrency (default in Swift 6) — every public type `Sendable`.
- Zero external SPM dependencies.
- Package name `swift-photos-automation`; single library product `PhotosAutomation`.
- Flat layout: `Sources/PhotosAutomation/*.swift`, `Tests/PhotosAutomationTests/*.swift` (no subfolders).
- Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`) — NOT XCTest.
- Error enums are `Error, Equatable, Sendable` with a `LocalizedError` extension providing `errorDescription`.
- Value types conform to `Equatable, Hashable, Identifiable, Sendable` where semantically free.
- Every public declaration gets a DocC comment (`///`).
- Integration tests are opt-in via `PHOTOS_AUTOMATION_INTEGRATION=1` using `.disabled(if:)` traits; plain `swift test` must pass with no permission prompts.
- Any test suite that invokes `NSAppleScriptRunner` for real carries the `.serialized` trait (`NSAppleScript` is non-reentrant inside test bundles).
- Every string interpolated into AppleScript source must be escaped (backslash first, then double-quote).
- Commit messages use Conventional Commits (`feat:`, `test:`, `docs:`, `chore:`, `ci:`).
- Run `swift build && swift test` before every commit; both must succeed.

## File Structure

| File | Responsibility |
|---|---|
| `Package.swift` | SPM manifest |
| `Sources/PhotosAutomation/PhotosAutomation.swift` | Module-level DocC comment only |
| `Sources/PhotosAutomation/AppleScriptRunner.swift` | `AppleScriptRunner` protocol + `AppleScriptError` (copied from sibling) |
| `Sources/PhotosAutomation/NSAppleScriptRunner.swift` | Production runner (copied from sibling) |
| `Sources/PhotosAutomation/PhotoAsset.swift` | `PhotoAsset` + `PhotoMediaType` value types |
| `Sources/PhotosAutomation/PhotoAlbum.swift` | `PhotoAlbum` value type |
| `Sources/PhotosAutomation/PhotoSearchCriteria.swift` | Structured search criteria |
| `Sources/PhotosAutomation/PhotoServiceError.swift` | Domain error enum |
| `Sources/PhotosAutomation/PhotoLibraryStore.swift` | Store protocol |
| `Sources/PhotosAutomation/PhotoKitStore.swift` | Concrete PhotoKit implementation |
| `Sources/PhotosAutomation/Locked.swift` | Internal `NSLock` box for `performChanges` result capture |
| `Sources/PhotosAutomation/PhotoService.swift` | Public API: validation, orchestration, AppleScript generation/parsing |
| `Tests/PhotosAutomationTests/FakeAppleScriptRunner.swift` | Test fake (copied from sibling) |
| `Tests/PhotosAutomationTests/FakePhotoLibraryStore.swift` | Test fake for the store |
| `Tests/PhotosAutomationTests/ErrorTests.swift` | Error description tests |
| `Tests/PhotosAutomationTests/ModelTests.swift` | Value-type tests |
| `Tests/PhotosAutomationTests/PhotoServiceReadTests.swift` | listAlbums / listAssets / search / asset |
| `Tests/PhotosAutomationTests/PhotoServiceSearchTextTests.swift` | searchText script gen + parsing |
| `Tests/PhotosAutomationTests/PhotoServiceMetadataWriteTests.swift` | setTitle / setDescription / setKeywords |
| `Tests/PhotosAutomationTests/PhotoServiceOrganizeTests.swift` | album ops, favorite, export, imageData, import |
| `Tests/PhotosAutomationTests/NSAppleScriptRunnerTests.swift` | Live bridge tests (env-gated) |
| `Tests/PhotosAutomationTests/PhotoServiceIntegrationTests.swift` | Real-library end-to-end (env-gated) |
| `README.md`, `CLAUDE.md`, `LICENSE`, `VERSION`, `CHANGELOG.md`, `.spi.yml`, `.swiftformat`, `.gitignore` | Repo scaffolding |
| `release-please-config.json`, `.release-please-manifest.json`, `.github/**` | Release + CI scaffolding |

---

### Task 1: Package scaffolding

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `.swiftformat`
- Create: `.spi.yml`
- Create: `Sources/PhotosAutomation/PhotosAutomation.swift`
- Create: `Tests/PhotosAutomationTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a building, testing SPM package named `swift-photos-automation` with library product `PhotosAutomation`. Later tasks add files under `Sources/PhotosAutomation/` and `Tests/PhotosAutomationTests/` without touching `Package.swift`.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-photos-automation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PhotosAutomation", targets: ["PhotosAutomation"]),
    ],
    targets: [
        .target(name: "PhotosAutomation"),
        .testTarget(
            name: "PhotosAutomationTests",
            dependencies: ["PhotosAutomation"]
        ),
    ]
)
```

- [ ] **Step 2: Write `.gitignore`**

```
.DS_Store
.build/
.swiftpm/
*.xcodeproj
DerivedData/
```

- [ ] **Step 3: Write `LICENSE`** — standard MIT text with `Copyright (c) 2026 Chris Hall` (copy `~/git/swift-notes-automation/LICENSE` verbatim).

```bash
cp ~/git/swift-notes-automation/LICENSE LICENSE
```

- [ ] **Step 4: Write `.swiftformat`** (verbatim from swift-mail-automation)

```
# swiftformat config — matches repo house style.
# Run:  swiftformat .
# Lint: swiftformat . --lint

--swiftversion 6.0
--maxwidth 120

# Prefer `case let .foo(x)` over `case .foo(let x)`.
--patternlet hoist

# Don't indent `#if` contents — standard Swift style keeps them flush left.
--ifdef no-indent

# Keep short property / function bodies on one line — cleaner for helpers
# like `var nonEmpty: String? { isEmpty ? nil : self }` or tiny actor
# mutators.
--disable wrapPropertyBodies
--disable wrapFunctionBodies

# AppleScript embedded in multi-line string literals often exceeds maxwidth
# and we can't reflow it without breaking the script. `wrap` also tries to
# reflow string interpolations in ways that reduce readability — leave
# that to the author.
--disable wrap
```

- [ ] **Step 5: Write `.spi.yml`**

```yaml
# Swift Package Index config — tells SPI how to generate DocC for us.
# https://swiftpackageindex.com/SwiftPackageIndex/SPIManifest/documentation
version: 1
builder:
  configs:
    - documentation_targets: [PhotosAutomation]
      platform: macos
```

- [ ] **Step 6: Write `Sources/PhotosAutomation/PhotosAutomation.swift`** (module doc only — comments are valid Swift source)

```swift
/// PhotosAutomation — a Swift library for driving the Apple Photos library
/// on macOS.
///
/// Two complementary transports behind one `PhotoService` facade:
/// - **PhotoKit** (``PhotoKitStore``): structured search, metadata, export,
///   import, albums, favorites.
/// - **AppleScript** (``NSAppleScriptRunner``): writing titles, descriptions,
///   and keywords, plus free-text search — the operations PhotoKit does not
///   expose.
```

- [ ] **Step 7: Write `Tests/PhotosAutomationTests/SmokeTests.swift`**

```swift
import Testing
@testable import PhotosAutomation

@Suite struct SmokeTests {
    @Test func packageBuilds() {
        #expect(Bool(true))
    }
}
```

- [ ] **Step 8: Verify build and test**

Run: `swift build && swift test`
Expected: build succeeds; 1 test passes.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: scaffold swift package with SPI, swiftformat, MIT license"
```

---

### Task 2: AppleScript transport (runner protocol, production runner, fake, error tests)

**Files:**
- Create: `Sources/PhotosAutomation/AppleScriptRunner.swift`
- Create: `Sources/PhotosAutomation/NSAppleScriptRunner.swift`
- Create: `Tests/PhotosAutomationTests/FakeAppleScriptRunner.swift`
- Create: `Tests/PhotosAutomationTests/ErrorTests.swift`
- Create: `Tests/PhotosAutomationTests/NSAppleScriptRunnerTests.swift`
- Delete: `Tests/PhotosAutomationTests/SmokeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public protocol AppleScriptRunner: Sendable { func run(source: String) async throws -> String }`; `public enum AppleScriptError: Error, Equatable, Sendable { case runtime(String); case compile(String) }`; `public struct NSAppleScriptRunner: AppleScriptRunner { public init() }`; test-target `final class FakeAppleScriptRunner: AppleScriptRunner, @unchecked Sendable` with `queue(_:)`, `queueError(_:)`, `calls: [String]`, `defaultResponse`.

These are copied from `~/git/swift-notes-automation/Sources/NotesAutomation/` with doc comments adapted (mentions of Notes → Photos where they appear). The code is proven — do not redesign it.

- [ ] **Step 1: Write the failing error test** — `Tests/PhotosAutomationTests/ErrorTests.swift`

```swift
import Foundation
import Testing
@testable import PhotosAutomation

@Suite struct AppleScriptErrorTests {
    @Test func runtimeDescription() {
        let error = AppleScriptError.runtime("Photos got an error")
        #expect(error.errorDescription == "AppleScript runtime error: Photos got an error")
    }

    @Test func compileDescription() {
        let error = AppleScriptError.compile("bad source")
        #expect(error.errorDescription == "AppleScript compile error: bad source")
    }

    @Test func equatable() {
        #expect(AppleScriptError.runtime("x") == AppleScriptError.runtime("x"))
        #expect(AppleScriptError.runtime("x") != AppleScriptError.compile("x"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL — `cannot find 'AppleScriptError' in scope`.

- [ ] **Step 3: Write `Sources/PhotosAutomation/AppleScriptRunner.swift`**

```swift
import Foundation

/// A type that can execute AppleScript source and return its scalar result.
///
/// The protocol exists so service code that drives Photos (or any other
/// AppleScript-scriptable application) can be unit-tested without invoking
/// the real system bridge. Production callers use ``NSAppleScriptRunner``;
/// tests inject a fake that returns canned responses.
///
/// Conforming types must be `Sendable` so a single runner can be shared
/// across concurrent service calls.
public protocol AppleScriptRunner: Sendable {
    /// Executes `source` and returns the scalar result as a string.
    ///
    /// - Parameter source: Complete, unescaped AppleScript source code.
    ///   The runner handles compilation.
    /// - Returns: The result of the final AppleScript expression, coerced
    ///   to `String`. Returns `""` when the script produces no string
    ///   result.
    /// - Throws: ``AppleScriptError/runtime(_:)`` when AppleScript
    ///   reports an error at execution time — for example, the target
    ///   application is not running, Automation permission is denied, or
    ///   the script executes an `error "…"` statement.
    ///   ``AppleScriptError/compile(_:)`` when `source` cannot be
    ///   compiled into an executable script.
    func run(source: String) async throws -> String
}

/// Errors surfaced by an ``AppleScriptRunner`` execution.
///
/// The two cases mirror the two failure modes of `NSAppleScript`: an
/// error at construction time (compile) and an error at execution time
/// (runtime). In practice nearly all failures are `runtime` — Apple's
/// script compiler is permissive and defers most parsing until execution.
public enum AppleScriptError: Error, Equatable, Sendable {
    /// The script compiled but AppleScript signaled an error during
    /// execution.
    ///
    /// The associated value is the message from
    /// `NSAppleScriptErrorMessage` — falling back to
    /// `NSAppleScriptErrorBriefMessage` or the numeric error code when
    /// the primary key is missing.
    case runtime(String)

    /// The script source could not be compiled into an `NSAppleScript`
    /// instance.
    ///
    /// Extremely rare in practice; `NSAppleScript`'s initializer is very
    /// permissive about what it accepts.
    case compile(String)
}

extension AppleScriptError: LocalizedError {
    /// Human-readable description suitable for logs and user display.
    public var errorDescription: String? {
        switch self {
        case .runtime(let message):
            return "AppleScript runtime error: \(message)"
        case .compile(let message):
            return "AppleScript compile error: \(message)"
        }
    }
}
```

- [ ] **Step 4: Write `Sources/PhotosAutomation/NSAppleScriptRunner.swift`**

```swift
import Foundation

/// Production ``AppleScriptRunner`` backed by `NSAppleScript`.
///
/// Each call to ``run(source:)`` constructs and executes its own
/// `NSAppleScript` inside a `Task.detached`. `NSAppleScript` is not
/// `Sendable`, so confining its lifetime to a single cooperative task
/// keeps the library safe under Swift 6 strict concurrency and sidesteps
/// Foundation's thread-affinity concerns.
///
/// Using `NSAppleScript` rather than shelling out to `osascript` avoids
/// the per-call subprocess cost and the shell-escaping hazards that come
/// with building a command line from untrusted strings.
public struct NSAppleScriptRunner: AppleScriptRunner {
    /// Creates a runner.
    ///
    /// There is no per-instance configuration — all state lives in the
    /// per-call `NSAppleScript` object.
    public init() {}

    /// Compiles and executes `source`, returning the scalar result as a
    /// `String`.
    ///
    /// - Parameter source: AppleScript source code.
    /// - Returns: `descriptor.stringValue` of the final descriptor, or
    ///   `""` when the result cannot be coerced to a string.
    /// - Throws: ``AppleScriptError/compile(_:)`` when the source cannot
    ///   be constructed; ``AppleScriptError/runtime(_:)`` when
    ///   AppleScript reports an error at execution time.
    public func run(source: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) { () throws -> String in
            guard let script = NSAppleScript(source: source) else {
                throw AppleScriptError.compile("Failed to construct NSAppleScript")
            }
            var errorInfo: NSDictionary?
            let descriptor = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String
                    ?? errorInfo[NSAppleScript.errorBriefMessage] as? String
                    ?? "AppleScript error \(errorInfo[NSAppleScript.errorNumber] ?? "?")"
                throw AppleScriptError.runtime(message)
            }
            return descriptor.stringValue ?? ""
        }.value
    }
}
```

- [ ] **Step 5: Write `Tests/PhotosAutomationTests/FakeAppleScriptRunner.swift`**

```swift
import Foundation
import PhotosAutomation

/// In-memory AppleScriptRunner for tests. Records every script it was asked
/// to run, and replies with a queued result or a constant.
final class FakeAppleScriptRunner: AppleScriptRunner, @unchecked Sendable {
    /// Responses to hand out in FIFO order. When empty, returns
    /// `defaultResponse`.
    var responses: [Result<String, AppleScriptError>] = []
    var defaultResponse: Result<String, AppleScriptError> = .success("")

    private(set) var calls: [String] = []

    func run(source: String) async throws -> String {
        calls.append(source)
        let r = responses.isEmpty ? defaultResponse : responses.removeFirst()
        switch r {
        case .success(let s): return s
        case .failure(let e): throw e
        }
    }

    func queue(_ result: String) {
        responses.append(.success(result))
    }
    func queueError(_ msg: String) {
        responses.append(.failure(.runtime(msg)))
    }
}
```

- [ ] **Step 6: Write `Tests/PhotosAutomationTests/NSAppleScriptRunnerTests.swift`** (env-gated live bridge tests — `NSAppleScript` is non-reentrant in test bundles, hence `.serialized` and the gate)

```swift
import Foundation
import Testing
@testable import PhotosAutomation

/// Exercises the real `NSAppleScript` bridge with trivial scripts (no
/// Photos permission needed). Opt-in because the bridge misbehaves inside
/// test bundles on recent macOS — parallel invocations from the same
/// process flake with error -1751 even for `return "hello"`.
@Suite("NSAppleScriptRunner live", .serialized)
struct NSAppleScriptRunnerTests {
    static let enabled = ProcessInfo.processInfo.environment["PHOTOS_AUTOMATION_INTEGRATION"] == "1"
    static let enabledComment: Comment = "set PHOTOS_AUTOMATION_INTEGRATION=1 to run live AppleScript tests"

    @Test("returns scalar string", .disabled(if: !enabled, enabledComment))
    func scalar() async throws {
        let out = try await NSAppleScriptRunner().run(source: #"return "hello""#)
        #expect(out == "hello")
    }

    @Test("empty result coerces to empty string", .disabled(if: !enabled, enabledComment))
    func emptyResult() async throws {
        let out = try await NSAppleScriptRunner().run(source: "return")
        #expect(out == "")
    }

    @Test("runtime error surfaces as AppleScriptError.runtime", .disabled(if: !enabled, enabledComment))
    func runtimeError() async {
        await #expect(throws: AppleScriptError.runtime("boom")) {
            _ = try await NSAppleScriptRunner().run(source: #"error "boom""#)
        }
    }
}
```

- [ ] **Step 7: Delete `Tests/PhotosAutomationTests/SmokeTests.swift`** — superseded by real tests.

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test`
Expected: PASS — error tests green, live suite skipped (env var unset).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add AppleScript transport (runner protocol, NSAppleScript impl, test fake)"
```

---

### Task 3: Domain models and error type

**Files:**
- Create: `Sources/PhotosAutomation/PhotoAsset.swift`
- Create: `Sources/PhotosAutomation/PhotoAlbum.swift`
- Create: `Sources/PhotosAutomation/PhotoSearchCriteria.swift`
- Create: `Sources/PhotosAutomation/PhotoServiceError.swift`
- Create: `Tests/PhotosAutomationTests/ModelTests.swift`
- Modify: `Tests/PhotosAutomationTests/ErrorTests.swift` (add `PhotoServiceError` suite)

**Interfaces:**
- Consumes: nothing.
- Produces (exact shapes later tasks depend on):
  - `PhotoAsset(id:originalFilename:creationDate:mediaType:isFavorite:pixelWidth:pixelHeight:latitude:longitude:title:itemDescription:keywords:)` — `title`, `itemDescription`, `keywords` are `var` (service mutates them during hydration), everything else `let`.
  - `PhotoMediaType: String` enum — `.image, .video, .audio, .unknown`.
  - `PhotoAlbum(id:title:assetCount:)`.
  - `PhotoSearchCriteria(startDate:endDate:mediaType:favoritesOnly:albumId:limit:)` with defaults `(nil, nil, nil, false, nil, 50)`.
  - `PhotoServiceError { invalidInput(String), notFound(String), permissionDenied, operationFailed(String) }`.

- [ ] **Step 1: Write the failing tests**

`Tests/PhotosAutomationTests/ModelTests.swift`:

```swift
import Foundation
import Testing
@testable import PhotosAutomation

@Suite struct ModelTests {
    @Test func photoAssetDefaultsAndIdentity() {
        let asset = PhotoAsset(id: "ABC/L0/001")
        #expect(asset.id == "ABC/L0/001")
        #expect(asset.mediaType == .image)
        #expect(asset.isFavorite == false)
        #expect(asset.title == nil)
        #expect(asset.keywords == nil)
    }

    @Test func photoAssetEquatableHashable() {
        let a = PhotoAsset(id: "A")
        let b = PhotoAsset(id: "A")
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
    }

    @Test func photoAlbum() {
        let album = PhotoAlbum(id: "alb1", title: "Trips", assetCount: 3)
        #expect(album.id == "alb1")
        #expect(album.title == "Trips")
        #expect(album.assetCount == 3)
    }

    @Test func searchCriteriaDefaults() {
        let criteria = PhotoSearchCriteria()
        #expect(criteria.startDate == nil)
        #expect(criteria.endDate == nil)
        #expect(criteria.mediaType == nil)
        #expect(criteria.favoritesOnly == false)
        #expect(criteria.albumId == nil)
        #expect(criteria.limit == 50)
    }

    @Test func mediaTypeRawValues() {
        #expect(PhotoMediaType.image.rawValue == "image")
        #expect(PhotoMediaType.video.rawValue == "video")
        #expect(PhotoMediaType.audio.rawValue == "audio")
        #expect(PhotoMediaType.unknown.rawValue == "unknown")
    }
}
```

Append to `Tests/PhotosAutomationTests/ErrorTests.swift`:

```swift
@Suite struct PhotoServiceErrorTests {
    @Test func descriptions() {
        #expect(PhotoServiceError.invalidInput("id must not be empty").errorDescription
            == "Invalid input: id must not be empty")
        #expect(PhotoServiceError.notFound("asset X").errorDescription
            == "Not found: asset X")
        #expect(PhotoServiceError.permissionDenied.errorDescription
            == "Photos library access denied — grant access in System Settings → Privacy & Security → Photos")
        #expect(PhotoServiceError.operationFailed("boom").errorDescription
            == "Photos operation failed: boom")
    }

    @Test func equatable() {
        #expect(PhotoServiceError.permissionDenied == PhotoServiceError.permissionDenied)
        #expect(PhotoServiceError.notFound("a") != PhotoServiceError.notFound("b"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `cannot find 'PhotoAsset' in scope` (and siblings).

- [ ] **Step 3: Write the implementations**

`Sources/PhotosAutomation/PhotoAsset.swift`:

```swift
import Foundation

/// The kind of media a ``PhotoAsset`` holds.
///
/// Raw values are stable lowercase strings so consumers (e.g. MCP tool
/// schemas) can round-trip them without a mapping table.
public enum PhotoMediaType: String, Equatable, Hashable, Sendable, CaseIterable {
    case image
    case video
    case audio
    case unknown
}

/// A single item in the Photos library — photo, video, or audio clip.
///
/// `id` is PhotoKit's `localIdentifier` (e.g. `"4AF382AC-…/L0/001"`),
/// which is the same string Photos' AppleScript dictionary exposes as
/// `media item id` — so one ID works across both transports.
///
/// `title`, `itemDescription`, and `keywords` are only populated by
/// ``PhotoService/asset(id:)``, which reads them via AppleScript —
/// PhotoKit does not expose them. They are `nil` in list/search results.
public struct PhotoAsset: Equatable, Hashable, Identifiable, Sendable {
    /// PhotoKit `localIdentifier` / AppleScript `media item id`.
    public let id: String
    /// Original filename at import time (e.g. `IMG_0042.HEIC`), when known.
    public let originalFilename: String?
    /// When the photo was taken (EXIF capture date), when known.
    public let creationDate: Date?
    /// Kind of media.
    public let mediaType: PhotoMediaType
    /// Whether the user has favorited this asset.
    public let isFavorite: Bool
    /// Pixel width of the asset (0 when unknown).
    public let pixelWidth: Int
    /// Pixel height of the asset (0 when unknown).
    public let pixelHeight: Int
    /// GPS latitude, when the asset has location data.
    public let latitude: Double?
    /// GPS longitude, when the asset has location data.
    public let longitude: Double?
    /// User-assigned title ("name" in Photos). AppleScript-sourced.
    public var title: String?
    /// User-assigned description/caption. AppleScript-sourced.
    public var itemDescription: String?
    /// User-assigned keywords. AppleScript-sourced.
    public var keywords: [String]?

    /// Creates an asset. All metadata parameters default to empty/unknown
    /// so tests and fakes can construct minimal instances.
    public init(
        id: String,
        originalFilename: String? = nil,
        creationDate: Date? = nil,
        mediaType: PhotoMediaType = .image,
        isFavorite: Bool = false,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        latitude: Double? = nil,
        longitude: Double? = nil,
        title: String? = nil,
        itemDescription: String? = nil,
        keywords: [String]? = nil
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.creationDate = creationDate
        self.mediaType = mediaType
        self.isFavorite = isFavorite
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.latitude = latitude
        self.longitude = longitude
        self.title = title
        self.itemDescription = itemDescription
        self.keywords = keywords
    }
}
```

`Sources/PhotosAutomation/PhotoAlbum.swift`:

```swift
import Foundation

/// A user-created album in the Photos library.
public struct PhotoAlbum: Equatable, Hashable, Identifiable, Sendable {
    /// PhotoKit `localIdentifier` of the underlying `PHAssetCollection`.
    public let id: String
    /// The album's display title.
    public let title: String
    /// Number of assets in the album.
    public let assetCount: Int

    /// Creates an album value.
    public init(id: String, title: String, assetCount: Int) {
        self.id = id
        self.title = title
        self.assetCount = assetCount
    }
}
```

`Sources/PhotosAutomation/PhotoSearchCriteria.swift`:

```swift
import Foundation

/// Structured search criteria evaluated by PhotoKit predicates.
///
/// All fields are optional filters; unset fields match everything.
/// For free-text search (titles, keywords, detected content), use
/// ``PhotoService/searchText(_:limit:)`` instead — PhotoKit predicates
/// cannot match on those.
public struct PhotoSearchCriteria: Equatable, Sendable {
    /// Only assets captured on or after this date.
    public var startDate: Date?
    /// Only assets captured on or before this date.
    public var endDate: Date?
    /// Only assets of this media type.
    public var mediaType: PhotoMediaType?
    /// Only favorited assets.
    public var favoritesOnly: Bool
    /// Only assets in the album with this `localIdentifier`.
    public var albumId: String?
    /// Maximum number of results, newest first. Must be positive.
    public var limit: Int

    /// Creates criteria. Defaults match everything, newest 50 first.
    public init(
        startDate: Date? = nil,
        endDate: Date? = nil,
        mediaType: PhotoMediaType? = nil,
        favoritesOnly: Bool = false,
        albumId: String? = nil,
        limit: Int = 50
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.mediaType = mediaType
        self.favoritesOnly = favoritesOnly
        self.albumId = albumId
        self.limit = limit
    }
}
```

`Sources/PhotosAutomation/PhotoServiceError.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add PhotoAsset, PhotoAlbum, PhotoSearchCriteria, PhotoServiceError models"
```

---

### Task 4: Store protocol and fake

**Files:**
- Create: `Sources/PhotosAutomation/PhotoLibraryStore.swift`
- Create: `Tests/PhotosAutomationTests/FakePhotoLibraryStore.swift`

**Interfaces:**
- Consumes: models from Task 3.
- Produces: the `PhotoLibraryStore` protocol below (Tasks 5–8 program against it; Tasks 9–11 implement it) and the test fake with knobs `albums`, `searchResults`, `assetsById`, `exportResult`, `imageDataResult`, `createdAlbum`, `importResult`, `errorToThrow`, plus recorders `calls: [String]` and `lastCriteria: PhotoSearchCriteria?`.

- [ ] **Step 1: Write `Sources/PhotosAutomation/PhotoLibraryStore.swift`** (protocol first — the fake conforming to it is its test)

```swift
import Foundation

/// Abstracts PhotoKit so ``PhotoService`` can be unit-tested without a
/// real Photos library or TCC grant.
///
/// Production implementation is ``PhotoKitStore``; tests inject a fake.
/// Implementations throw ``PhotoServiceError`` (`permissionDenied`,
/// `notFound`, `operationFailed`) — they never throw ``AppleScriptError``.
public protocol PhotoLibraryStore: Sendable {
    /// All user-created albums.
    func listAlbums() async throws -> [PhotoAlbum]
    /// Assets matching `criteria`, newest first, capped at `criteria.limit`.
    func assets(matching criteria: PhotoSearchCriteria) async throws -> [PhotoAsset]
    /// The asset with `id`, or `nil` when it doesn't exist.
    func asset(id: String) async throws -> PhotoAsset?
    /// The assets with the given ids. Unknown ids are silently omitted;
    /// result order is unspecified (callers re-order).
    func assets(ids: [String]) async throws -> [PhotoAsset]
    /// Writes each asset's original resource (photo or video file) into
    /// `directory`, creating it if needed. Returns the written file URLs.
    func exportOriginals(ids: [String], to directory: URL) async throws -> [URL]
    /// A JPEG rendition of the asset scaled to fit `maxDimension` pixels
    /// on its longest side.
    func imageData(id: String, maxDimension: Int) async throws -> Data
    /// Creates a new top-level album.
    func createAlbum(title: String) async throws -> PhotoAlbum
    /// Deletes the album (not its assets). Used by integration-test
    /// cleanup; asset deletion is deliberately unsupported (macOS shows a
    /// blocking confirmation dialog).
    func deleteAlbum(id: String) async throws
    /// Adds the assets to the album.
    func add(ids: [String], toAlbum albumId: String) async throws
    /// Removes the assets from the album.
    func remove(ids: [String], fromAlbum albumId: String) async throws
    /// Sets or clears the favorite flag.
    func setFavorite(id: String, _ isFavorite: Bool) async throws
    /// Imports the files at `urls` into the library and optionally into
    /// the album with `albumId`. Returns the created assets.
    func importFiles(urls: [URL], toAlbum albumId: String?) async throws -> [PhotoAsset]
}
```

- [ ] **Step 2: Write `Tests/PhotosAutomationTests/FakePhotoLibraryStore.swift`**

```swift
import Foundation
import PhotosAutomation

/// In-memory PhotoLibraryStore for tests. Records every call and returns
/// configurable canned results; set `errorToThrow` to make any call throw.
final class FakePhotoLibraryStore: PhotoLibraryStore, @unchecked Sendable {
    var albums: [PhotoAlbum] = []
    var searchResults: [PhotoAsset] = []
    var assetsById: [String: PhotoAsset] = [:]
    var exportResult: [URL] = []
    var imageDataResult = Data()
    var createdAlbum = PhotoAlbum(id: "new-album", title: "New", assetCount: 0)
    var importResult: [PhotoAsset] = []
    var errorToThrow: Error?

    private(set) var calls: [String] = []
    private(set) var lastCriteria: PhotoSearchCriteria?

    private func record(_ call: String) throws {
        calls.append(call)
        if let errorToThrow { throw errorToThrow }
    }

    func listAlbums() async throws -> [PhotoAlbum] {
        try record("listAlbums")
        return albums
    }

    func assets(matching criteria: PhotoSearchCriteria) async throws -> [PhotoAsset] {
        lastCriteria = criteria
        try record("assets(matching:)")
        return searchResults
    }

    func asset(id: String) async throws -> PhotoAsset? {
        try record("asset(\(id))")
        return assetsById[id]
    }

    func assets(ids: [String]) async throws -> [PhotoAsset] {
        try record("assets(ids: \(ids))")
        return ids.compactMap { assetsById[$0] }
    }

    func exportOriginals(ids: [String], to directory: URL) async throws -> [URL] {
        try record("exportOriginals(\(ids), to: \(directory.path))")
        return exportResult
    }

    func imageData(id: String, maxDimension: Int) async throws -> Data {
        try record("imageData(\(id), maxDimension: \(maxDimension))")
        return imageDataResult
    }

    func createAlbum(title: String) async throws -> PhotoAlbum {
        try record("createAlbum(\(title))")
        return createdAlbum
    }

    func deleteAlbum(id: String) async throws {
        try record("deleteAlbum(\(id))")
    }

    func add(ids: [String], toAlbum albumId: String) async throws {
        try record("add(\(ids), toAlbum: \(albumId))")
    }

    func remove(ids: [String], fromAlbum albumId: String) async throws {
        try record("remove(\(ids), fromAlbum: \(albumId))")
    }

    func setFavorite(id: String, _ isFavorite: Bool) async throws {
        try record("setFavorite(\(id), \(isFavorite))")
    }

    func importFiles(urls: [URL], toAlbum albumId: String?) async throws -> [PhotoAsset] {
        try record("importFiles(\(urls.map(\.lastPathComponent)), toAlbum: \(albumId ?? "nil"))")
        return importResult
    }
}
```

- [ ] **Step 3: Verify build and existing tests still pass**

Run: `swift build && swift test`
Expected: PASS (the fake compiling against the protocol is the check here; behavior tests come with the service).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add PhotoLibraryStore protocol and test fake"
```

---

### Task 5: PhotoService read operations

**Files:**
- Create: `Sources/PhotosAutomation/PhotoService.swift`
- Create: `Tests/PhotosAutomationTests/PhotoServiceReadTests.swift`

**Interfaces:**
- Consumes: `PhotoLibraryStore` (Task 4), `AppleScriptRunner` (Task 2), models (Task 3).
- Produces: `public struct PhotoService: Sendable` with `init(store:runner:)`, `listAlbums()`, `listAssets(albumId:limit:)`, `search(criteria:)`, `asset(id:)`, plus internal statics `metadataScript(id:)`, `parseMetadataLine(_:)`, `escapeForAppleScript(_:)`. Tasks 6–8 extend this same struct.

- [ ] **Step 1: Write the failing tests** — `Tests/PhotosAutomationTests/PhotoServiceReadTests.swift`

```swift
import Foundation
import Testing
@testable import PhotosAutomation

@Suite struct PhotoServiceReadTests {
    private func makeService(
        store: FakePhotoLibraryStore = FakePhotoLibraryStore(),
        runner: FakeAppleScriptRunner = FakeAppleScriptRunner()
    ) -> PhotoService {
        PhotoService(store: store, runner: runner)
    }

    // MARK: listAlbums

    @Test func listAlbumsReturnsStoreAlbums() async throws {
        let store = FakePhotoLibraryStore()
        store.albums = [PhotoAlbum(id: "a1", title: "Trips", assetCount: 3)]
        let albums = try await makeService(store: store).listAlbums()
        #expect(albums == [PhotoAlbum(id: "a1", title: "Trips", assetCount: 3)])
    }

    // MARK: listAssets

    @Test func listAssetsBuildsCriteriaFromArguments() async throws {
        let store = FakePhotoLibraryStore()
        _ = try await makeService(store: store).listAssets(albumId: "alb1", limit: 10)
        #expect(store.lastCriteria == PhotoSearchCriteria(albumId: "alb1", limit: 10))
    }

    @Test func listAssetsDefaults() async throws {
        let store = FakePhotoLibraryStore()
        _ = try await makeService(store: store).listAssets()
        #expect(store.lastCriteria == PhotoSearchCriteria())
    }

    @Test func listAssetsRejectsNonPositiveLimit() async {
        await #expect(throws: PhotoServiceError.invalidInput("limit must be positive")) {
            _ = try await self.makeService().listAssets(limit: 0)
        }
    }

    @Test func listAssetsRejectsEmptyAlbumId() async {
        await #expect(throws: PhotoServiceError.invalidInput("albumId must not be empty")) {
            _ = try await self.makeService().listAssets(albumId: "  ")
        }
    }

    // MARK: search

    @Test func searchPassesCriteriaThrough() async throws {
        let store = FakePhotoLibraryStore()
        store.searchResults = [PhotoAsset(id: "X")]
        let criteria = PhotoSearchCriteria(favoritesOnly: true, limit: 5)
        let results = try await makeService(store: store).search(criteria: criteria)
        #expect(results == [PhotoAsset(id: "X")])
        #expect(store.lastCriteria == criteria)
    }

    @Test func searchRejectsNonPositiveLimit() async {
        await #expect(throws: PhotoServiceError.invalidInput("limit must be positive")) {
            _ = try await self.makeService().search(criteria: PhotoSearchCriteria(limit: -1))
        }
    }

    // MARK: asset(id:)

    @Test func assetRejectsEmptyId() async {
        await #expect(throws: PhotoServiceError.invalidInput("id must not be empty")) {
            _ = try await self.makeService().asset(id: "")
        }
    }

    @Test func assetNotFoundThrows() async {
        await #expect(throws: PhotoServiceError.notFound("asset missing-id")) {
            _ = try await self.makeService().asset(id: "missing-id")
        }
    }

    @Test func assetHydratesMetadataFromAppleScript() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById["A/L0/001"] = PhotoAsset(id: "A/L0/001")
        let runner = FakeAppleScriptRunner()
        runner.queue("Sunset\tGolden hour\tbeach,sunset")
        let asset = try await makeService(store: store, runner: runner).asset(id: "A/L0/001")
        #expect(asset.title == "Sunset")
        #expect(asset.itemDescription == "Golden hour")
        #expect(asset.keywords == ["beach", "sunset"])
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].contains(#"media item id "A/L0/001""#))
    }

    @Test func assetEmptyMetadataStaysNil() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById["A"] = PhotoAsset(id: "A")
        let runner = FakeAppleScriptRunner()
        runner.queue("\t\t")
        let asset = try await makeService(store: store, runner: runner).asset(id: "A")
        #expect(asset.title == nil)
        #expect(asset.itemDescription == nil)
        #expect(asset.keywords == nil)
    }

    @Test func assetSurvivesAppleScriptFailure() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById["A"] = PhotoAsset(id: "A")
        let runner = FakeAppleScriptRunner()
        runner.queueError("Photos is not running")
        let asset = try await makeService(store: store, runner: runner).asset(id: "A")
        #expect(asset.id == "A")
        #expect(asset.title == nil)
    }

    // MARK: parse helper

    @Test func parseMetadataLineMalformedReturnsNils() {
        let meta = PhotoService.parseMetadataLine("only-one-field")
        #expect(meta.title == nil)
        #expect(meta.description == nil)
        #expect(meta.keywords == nil)
    }

    @Test func escapeForAppleScript() {
        #expect(PhotoService.escapeForAppleScript(#"say "hi" \now"#) == #"say \"hi\" \\now"#)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `cannot find 'PhotoService' in scope`.

- [ ] **Step 3: Write `Sources/PhotosAutomation/PhotoService.swift`**

```swift
import Foundation

/// High-level facade over the Photos library.
///
/// Orchestrates two transports:
/// - a ``PhotoLibraryStore`` (PhotoKit) for structured search, metadata,
///   export, import, albums, and favorites;
/// - an ``AppleScriptRunner`` for what PhotoKit cannot do — reading and
///   writing titles/descriptions/keywords, and free-text search.
///
/// The service is a value type with no mutable state: construct once and
/// share freely across concurrent callers.
public struct PhotoService: Sendable {
    private let store: PhotoLibraryStore
    private let runner: AppleScriptRunner

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - store: PhotoKit access. Defaults to ``PhotoKitStore`` in
    ///     production once Task 9 lands; until then callers pass one in.
    ///   - runner: AppleScript access. Defaults to ``NSAppleScriptRunner``.
    public init(store: PhotoLibraryStore, runner: AppleScriptRunner = NSAppleScriptRunner()) {
        self.store = store
        self.runner = runner
    }

    // MARK: - Reads

    /// All user-created albums.
    public func listAlbums() async throws -> [PhotoAlbum] {
        try await store.listAlbums()
    }

    /// Assets in the library (or one album), newest first.
    ///
    /// - Parameters:
    ///   - albumId: Restrict to this album's contents. `nil` = whole library.
    ///   - limit: Maximum results; must be positive.
    public func listAssets(albumId: String? = nil, limit: Int = 50) async throws -> [PhotoAsset] {
        try Self.validatePositive(limit)
        if let albumId {
            try Self.validateNonEmpty(albumId, name: "albumId")
        }
        return try await store.assets(matching: PhotoSearchCriteria(albumId: albumId, limit: limit))
    }

    /// Assets matching structured criteria (dates, media type, favorites,
    /// album), newest first. For free-text search use ``searchText(_:limit:)``.
    public func search(criteria: PhotoSearchCriteria) async throws -> [PhotoAsset] {
        try Self.validatePositive(criteria.limit)
        return try await store.assets(matching: criteria)
    }

    /// A single asset with full metadata.
    ///
    /// PhotoKit fields come from the store; `title`, `itemDescription`,
    /// and `keywords` are hydrated via AppleScript. Hydration is
    /// best-effort: if Photos.app is unreachable or Automation permission
    /// is missing, those three fields stay `nil` rather than failing the
    /// whole lookup.
    public func asset(id: String) async throws -> PhotoAsset {
        let id = try Self.validateNonEmpty(id, name: "id")
        guard var asset = try await store.asset(id: id) else {
            throw PhotoServiceError.notFound("asset \(id)")
        }
        if let line = try? await runner.run(source: Self.metadataScript(id: id)) {
            let meta = Self.parseMetadataLine(line)
            asset.title = meta.title
            asset.itemDescription = meta.description
            asset.keywords = meta.keywords
        }
        return asset
    }

    // MARK: - Validation helpers

    /// Returns the trimmed value, or throws `.invalidInput` when blank.
    @discardableResult
    static func validateNonEmpty(_ value: String, name: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PhotoServiceError.invalidInput("\(name) must not be empty")
        }
        return trimmed
    }

    /// Throws `.invalidInput` when `limit` is not positive.
    static func validatePositive(_ limit: Int) throws {
        guard limit > 0 else {
            throw PhotoServiceError.invalidInput("limit must be positive")
        }
    }

    // MARK: - AppleScript generation & parsing

    /// Escapes a string for interpolation inside a double-quoted
    /// AppleScript string literal. Backslashes first, then quotes.
    static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Script returning `title<tab>description<tab>kw1,kw2` for one asset.
    ///
    /// `missing value` fields are coerced to `""` inside the script so the
    /// Swift-side parser can rely on a clean three-field line.
    static func metadataScript(id: String) -> String {
        let escaped = escapeForAppleScript(id)
        return """
        tell application "Photos"
            set m to media item id "\(escaped)"
            set t to name of m
            if t is missing value then set t to ""
            set d to description of m
            if d is missing value then set d to ""
            set kl to ""
            set kws to keywords of m
            if kws is not missing value then
                set AppleScript's text item delimiters to ","
                set kl to kws as text
                set AppleScript's text item delimiters to ""
            end if
            return t & tab & d & tab & kl
        end tell
        """
    }

    /// Parses ``metadataScript(id:)`` output. Empty fields become `nil`;
    /// a malformed line (wrong field count) yields all-`nil` — the caller
    /// treats metadata as best-effort.
    static func parseMetadataLine(_ line: String) -> (title: String?, description: String?, keywords: [String]?) {
        let fields = line.components(separatedBy: "\t")
        guard fields.count == 3 else { return (nil, nil, nil) }
        let title = fields[0].isEmpty ? nil : fields[0]
        let description = fields[1].isEmpty ? nil : fields[1]
        let keywords = fields[2].split(separator: ",").map(String.init)
        return (title, description, keywords.isEmpty ? nil : keywords)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add PhotoService read operations with AppleScript metadata hydration"
```

---

### Task 6: PhotoService free-text search

**Files:**
- Modify: `Sources/PhotosAutomation/PhotoService.swift` (add `searchText` + statics `searchScript(query:limit:)`, `parseIdLines(_:)`)
- Create: `Tests/PhotosAutomationTests/PhotoServiceSearchTextTests.swift`

**Interfaces:**
- Consumes: `PhotoService` (Task 5), `FakePhotoLibraryStore.assetsById`, `FakeAppleScriptRunner.queue(_:)`.
- Produces: `searchText(_ query: String, limit: Int = 25) async throws -> [PhotoAsset]`.

- [ ] **Step 1: Write the failing tests** — `Tests/PhotosAutomationTests/PhotoServiceSearchTextTests.swift`

```swift
import Foundation
import Testing
@testable import PhotosAutomation

@Suite struct PhotoServiceSearchTextTests {
    @Test func rejectsEmptyQuery() async {
        let service = PhotoService(store: FakePhotoLibraryStore(), runner: FakeAppleScriptRunner())
        await #expect(throws: PhotoServiceError.invalidInput("query must not be empty")) {
            _ = try await service.searchText("   ")
        }
    }

    @Test func rejectsNonPositiveLimit() async {
        let service = PhotoService(store: FakePhotoLibraryStore(), runner: FakeAppleScriptRunner())
        await #expect(throws: PhotoServiceError.invalidInput("limit must be positive")) {
            _ = try await service.searchText("beach", limit: 0)
        }
    }

    @Test func hydratesIdsInScriptOrder() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById = ["B": PhotoAsset(id: "B"), "A": PhotoAsset(id: "A")]
        let runner = FakeAppleScriptRunner()
        runner.queue("B\nA\n")
        let service = PhotoService(store: store, runner: runner)
        let results = try await service.searchText("beach")
        #expect(results.map(\.id) == ["B", "A"])
    }

    @Test func unknownIdsAreOmitted() async throws {
        let store = FakePhotoLibraryStore()
        store.assetsById = ["A": PhotoAsset(id: "A")]
        let runner = FakeAppleScriptRunner()
        runner.queue("A\nGONE\n")
        let service = PhotoService(store: store, runner: runner)
        let results = try await service.searchText("beach")
        #expect(results.map(\.id) == ["A"])
    }

    @Test func emptyScriptOutputReturnsEmptyWithoutStoreCall() async throws {
        let store = FakePhotoLibraryStore()
        let runner = FakeAppleScriptRunner()
        runner.queue("")
        let service = PhotoService(store: store, runner: runner)
        let results = try await service.searchText("nothing")
        #expect(results.isEmpty)
        #expect(store.calls.isEmpty)
    }

    @Test func scriptEmbedsEscapedQueryAndLimit() async throws {
        let runner = FakeAppleScriptRunner()
        let service = PhotoService(store: FakePhotoLibraryStore(), runner: runner)
        _ = try await service.searchText(#"kids "party""#, limit: 7)
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].contains(#"search for "kids \"party\"""#))
        #expect(runner.calls[0].contains("if n > 7 then set n to 7"))
    }

    @Test func parseIdLinesTrimsAndSkipsBlanks() {
        #expect(PhotoService.parseIdLines(" A \n\nB\n") == ["A", "B"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `value of type 'PhotoService' has no member 'searchText'`.

- [ ] **Step 3: Add to `PhotoService.swift`** (new `// MARK: - Free-text search` section)

```swift
    // MARK: - Free-text search

    /// Free-text search via Photos' own search engine (AppleScript
    /// `search for`), which matches titles, keywords, and detected content
    /// — none of which PhotoKit predicates can reach.
    ///
    /// Returned assets preserve Photos' relevance order. IDs that Photos
    /// returns but PhotoKit cannot resolve are silently omitted.
    ///
    /// - Parameters:
    ///   - query: Search text; must not be blank.
    ///   - limit: Maximum results; must be positive.
    public func searchText(_ query: String, limit: Int = 25) async throws -> [PhotoAsset] {
        let query = try Self.validateNonEmpty(query, name: "query")
        try Self.validatePositive(limit)
        let output = try await runner.run(source: Self.searchScript(query: query, limit: limit))
        let ids = Self.parseIdLines(output)
        guard !ids.isEmpty else { return [] }
        let assets = try await store.assets(ids: ids)
        let byId = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    /// Script running Photos' `search for` and returning matched ids,
    /// one per line, capped at `limit`.
    static func searchScript(query: String, limit: Int) -> String {
        let escaped = escapeForAppleScript(query)
        return """
        tell application "Photos"
            set found to search for "\(escaped)"
            set out to ""
            set n to count of found
            if n > \(limit) then set n to \(limit)
            repeat with i from 1 to n
                set out to out & (id of item i of found) & linefeed
            end repeat
            return out
        end tell
        """
    }

    /// Splits script output into trimmed, non-empty id lines.
    static func parseIdLines(_ output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add free-text search via Photos AppleScript search"
```

---

### Task 7: PhotoService metadata writes

**Files:**
- Modify: `Sources/PhotosAutomation/PhotoService.swift` (add `setTitle`, `setDescription`, `setKeywords` + statics `setTitleScript`, `setDescriptionScript`, `setKeywordsScript`)
- Create: `Tests/PhotosAutomationTests/PhotoServiceMetadataWriteTests.swift`

**Interfaces:**
- Consumes: `PhotoService` (Tasks 5–6).
- Produces: `setTitle(id:_:)`, `setDescription(id:_:)`, `setKeywords(id:_:)` — all `async throws`, all AppleScript-only (no store calls). Empty string / empty array clears the field. `AppleScriptError` propagates to the caller untranslated (matches sibling libraries; the MCP tool catches both error types).

- [ ] **Step 1: Write the failing tests** — `Tests/PhotosAutomationTests/PhotoServiceMetadataWriteTests.swift`

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `has no member 'setTitle'`.

- [ ] **Step 3: Add to `PhotoService.swift`** (new `// MARK: - Metadata writes (AppleScript)` section)

```swift
    // MARK: - Metadata writes (AppleScript)

    /// Sets the asset's title ("name" in Photos). Pass `""` to clear.
    ///
    /// PhotoKit cannot write titles — this goes through Photos.app via
    /// AppleScript, so it requires Automation permission for Photos.
    /// - Throws: ``PhotoServiceError/invalidInput(_:)`` for a blank id;
    ///   ``AppleScriptError`` when Photos.app rejects the script.
    public func setTitle(id: String, _ title: String) async throws {
        let id = try Self.validateNonEmpty(id, name: "id")
        _ = try await runner.run(source: Self.setTitleScript(id: id, title: title))
    }

    /// Sets the asset's description/caption. Pass `""` to clear.
    ///
    /// Same transport and error behavior as ``setTitle(id:_:)``.
    public func setDescription(id: String, _ description: String) async throws {
        let id = try Self.validateNonEmpty(id, name: "id")
        _ = try await runner.run(source: Self.setDescriptionScript(id: id, description: description))
    }

    /// Replaces the asset's keyword list. Pass `[]` to clear.
    ///
    /// Same transport and error behavior as ``setTitle(id:_:)``.
    public func setKeywords(id: String, _ keywords: [String]) async throws {
        let id = try Self.validateNonEmpty(id, name: "id")
        _ = try await runner.run(source: Self.setKeywordsScript(id: id, keywords: keywords))
    }

    static func setTitleScript(id: String, title: String) -> String {
        """
        tell application "Photos"
            set name of media item id "\(escapeForAppleScript(id))" to "\(escapeForAppleScript(title))"
        end tell
        """
    }

    static func setDescriptionScript(id: String, description: String) -> String {
        """
        tell application "Photos"
            set description of media item id "\(escapeForAppleScript(id))" to "\(escapeForAppleScript(description))"
        end tell
        """
    }

    static func setKeywordsScript(id: String, keywords: [String]) -> String {
        let list = keywords.map { "\"\(escapeForAppleScript($0))\"" }.joined(separator: ", ")
        return """
        tell application "Photos"
            set keywords of media item id "\(escapeForAppleScript(id))" to {\(list)}
        end tell
        """
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add title/description/keyword writes via AppleScript"
```

---

### Task 8: PhotoService organize, export, and import

**Files:**
- Modify: `Sources/PhotosAutomation/PhotoService.swift` (add remaining public API)
- Create: `Tests/PhotosAutomationTests/PhotoServiceOrganizeTests.swift`

**Interfaces:**
- Consumes: `PhotoService`, `FakePhotoLibraryStore` knobs.
- Produces: `createAlbum(title:)`, `add(ids:toAlbum:)`, `remove(ids:fromAlbum:)`, `setFavorite(id:_:)`, `exportOriginals(ids:to:)`, `imageData(id:maxDimension:)`, `importFiles(urls:albumId:)`. This completes the `PhotoService` public surface.

- [ ] **Step 1: Write the failing tests** — `Tests/PhotosAutomationTests/PhotoServiceOrganizeTests.swift`

```swift
import Foundation
import Testing
@testable import PhotosAutomation

@Suite struct PhotoServiceOrganizeTests {
    private let store = FakePhotoLibraryStore()
    private var service: PhotoService {
        PhotoService(store: store, runner: FakeAppleScriptRunner())
    }

    // MARK: albums

    @Test func createAlbumPassesTitleThrough() async throws {
        store.createdAlbum = PhotoAlbum(id: "n1", title: "Trip", assetCount: 0)
        let album = try await service.createAlbum(title: "Trip")
        #expect(album == PhotoAlbum(id: "n1", title: "Trip", assetCount: 0))
        #expect(store.calls == ["createAlbum(Trip)"])
    }

    @Test func createAlbumRejectsEmptyTitle() async {
        await #expect(throws: PhotoServiceError.invalidInput("title must not be empty")) {
            _ = try await self.service.createAlbum(title: "")
        }
    }

    @Test func addRejectsEmptyIds() async {
        await #expect(throws: PhotoServiceError.invalidInput("ids must not be empty")) {
            try await self.service.add(ids: [], toAlbum: "alb")
        }
    }

    @Test func addRejectsBlankMember() async {
        await #expect(throws: PhotoServiceError.invalidInput("ids must not contain blank values")) {
            try await self.service.add(ids: ["ok", " "], toAlbum: "alb")
        }
    }

    @Test func addAndRemovePassThrough() async throws {
        try await service.add(ids: ["a"], toAlbum: "alb")
        try await service.remove(ids: ["a"], fromAlbum: "alb")
        #expect(store.calls == [#"add(["a"], toAlbum: alb)"#, #"remove(["a"], fromAlbum: alb)"#])
    }

    // MARK: favorite

    @Test func setFavoritePassesThrough() async throws {
        try await service.setFavorite(id: "a", true)
        #expect(store.calls == ["setFavorite(a, true)"])
    }

    // MARK: export

    @Test func exportPassesThrough() async throws {
        let dir = URL(fileURLWithPath: "/tmp/exports")
        store.exportResult = [dir.appendingPathComponent("IMG_1.HEIC")]
        let urls = try await service.exportOriginals(ids: ["a"], to: dir)
        #expect(urls == [dir.appendingPathComponent("IMG_1.HEIC")])
    }

    @Test func exportRejectsEmptyIds() async {
        await #expect(throws: PhotoServiceError.invalidInput("ids must not be empty")) {
            _ = try await self.service.exportOriginals(ids: [], to: URL(fileURLWithPath: "/tmp"))
        }
    }

    // MARK: imageData

    @Test func imageDataPassesThrough() async throws {
        store.imageDataResult = Data([0xFF, 0xD8])
        let data = try await service.imageData(id: "a", maxDimension: 512)
        #expect(data == Data([0xFF, 0xD8]))
        #expect(store.calls == ["imageData(a, maxDimension: 512)"])
    }

    @Test func imageDataDefaultsTo1024() async throws {
        _ = try await service.imageData(id: "a")
        #expect(store.calls == ["imageData(a, maxDimension: 1024)"])
    }

    @Test func imageDataRejectsNonPositiveDimension() async {
        await #expect(throws: PhotoServiceError.invalidInput("maxDimension must be positive")) {
            _ = try await self.service.imageData(id: "a", maxDimension: 0)
        }
    }

    // MARK: import

    @Test func importRejectsEmptyURLs() async {
        await #expect(throws: PhotoServiceError.invalidInput("urls must not be empty")) {
            _ = try await self.service.importFiles(urls: [])
        }
    }

    @Test func importRejectsMissingFile() async {
        let missing = URL(fileURLWithPath: "/nonexistent/nope.png")
        await #expect(throws: PhotoServiceError.invalidInput("file does not exist: /nonexistent/nope.png")) {
            _ = try await self.service.importFiles(urls: [missing])
        }
    }

    @Test func importPassesThroughForExistingFile() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-automation-test-\(UUID().uuidString).png")
        try Data([0x89, 0x50]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        store.importResult = [PhotoAsset(id: "new1")]
        let imported = try await service.importFiles(urls: [tmp], albumId: "alb")
        #expect(imported == [PhotoAsset(id: "new1")])
        #expect(store.calls == ["importFiles([\(tmp.lastPathComponent)], toAlbum: alb)"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — `has no member 'createAlbum'` (and siblings).

- [ ] **Step 3: Add to `PhotoService.swift`** (new `// MARK: - Organize, export, import` section)

```swift
    // MARK: - Organize, export, import

    /// Creates a new top-level album.
    public func createAlbum(title: String) async throws -> PhotoAlbum {
        let title = try Self.validateNonEmpty(title, name: "title")
        return try await store.createAlbum(title: title)
    }

    /// Adds assets to an album.
    public func add(ids: [String], toAlbum albumId: String) async throws {
        try Self.validateIds(ids)
        let albumId = try Self.validateNonEmpty(albumId, name: "albumId")
        try await store.add(ids: ids, toAlbum: albumId)
    }

    /// Removes assets from an album (the assets stay in the library).
    public func remove(ids: [String], fromAlbum albumId: String) async throws {
        try Self.validateIds(ids)
        let albumId = try Self.validateNonEmpty(albumId, name: "albumId")
        try await store.remove(ids: ids, fromAlbum: albumId)
    }

    /// Sets or clears the favorite flag on an asset.
    public func setFavorite(id: String, _ isFavorite: Bool) async throws {
        let id = try Self.validateNonEmpty(id, name: "id")
        try await store.setFavorite(id: id, isFavorite)
    }

    /// Exports each asset's original file (photo or video) into
    /// `directory`, creating the directory if needed.
    /// - Returns: URLs of the written files, in input order.
    public func exportOriginals(ids: [String], to directory: URL) async throws -> [URL] {
        try Self.validateIds(ids)
        return try await store.exportOriginals(ids: ids, to: directory)
    }

    /// A JPEG rendition scaled to fit `maxDimension` pixels on the longest
    /// side — suitable for returning as base64 image content from an MCP
    /// tool without touching disk.
    public func imageData(id: String, maxDimension: Int = 1024) async throws -> Data {
        let id = try Self.validateNonEmpty(id, name: "id")
        guard maxDimension > 0 else {
            throw PhotoServiceError.invalidInput("maxDimension must be positive")
        }
        return try await store.imageData(id: id, maxDimension: maxDimension)
    }

    /// Imports image/video files into the library, optionally adding them
    /// to an album. Every file must exist.
    /// - Returns: The created assets.
    public func importFiles(urls: [URL], albumId: String? = nil) async throws -> [PhotoAsset] {
        guard !urls.isEmpty else {
            throw PhotoServiceError.invalidInput("urls must not be empty")
        }
        for url in urls where !FileManager.default.fileExists(atPath: url.path) {
            throw PhotoServiceError.invalidInput("file does not exist: \(url.path)")
        }
        if let albumId {
            _ = try Self.validateNonEmpty(albumId, name: "albumId")
        }
        return try await store.importFiles(urls: urls, toAlbum: albumId)
    }

    /// Validates an id array: non-empty, no blank members.
    static func validateIds(_ ids: [String]) throws {
        guard !ids.isEmpty else {
            throw PhotoServiceError.invalidInput("ids must not be empty")
        }
        guard ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw PhotoServiceError.invalidInput("ids must not contain blank values")
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add album, favorite, export, imageData, and import operations"
```

---

### Task 9: PhotoKitStore — authorization and reads

PhotoKit cannot be faked in unit tests; this task is verified by compilation plus the Task 12 integration suite. Write the code carefully, build, and move on.

**Files:**
- Create: `Sources/PhotosAutomation/PhotoKitStore.swift`

**Interfaces:**
- Consumes: `PhotoLibraryStore` protocol, models, `PhotoServiceError`.
- Produces: `public struct PhotoKitStore: PhotoLibraryStore { public init() }` with reads implemented; write methods added in Tasks 10–11 (this task stubs them with `fatalError` — they must be replaced before Task 12; grep for `fatalError` at Task 11's end).

- [ ] **Step 1: Write `Sources/PhotosAutomation/PhotoKitStore.swift`**

```swift
import Foundation
import Photos

/// Production ``PhotoLibraryStore`` backed by PhotoKit.
///
/// Requires Photos library access (TCC). The first call from an
/// unauthorized process triggers the system permission prompt; a denied
/// state surfaces as ``PhotoServiceError/permissionDenied``.
///
/// > Note: The process needs a usage description to request access. App
/// > bundles declare `NSPhotoLibraryUsageDescription` in Info.plist;
/// > bare executables (like apple-swift-mcp) embed one via the
/// > `-sectcreate __TEXT __info_plist` linker flag.
public struct PhotoKitStore: PhotoLibraryStore {
    /// Creates a store. Stateless — all state lives in PhotoKit.
    public init() {}

    // MARK: - Authorization

    /// Ensures read/write authorization, requesting it when undetermined.
    func ensureAuthorized() async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            throw PhotoServiceError.permissionDenied
        }
    }

    // MARK: - Reads

    public func listAlbums() async throws -> [PhotoAlbum] {
        try await ensureAuthorized()
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: nil
        )
        var albums: [PhotoAlbum] = []
        for i in 0..<collections.count {
            let collection = collections.object(at: i)
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            albums.append(PhotoAlbum(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "",
                assetCount: count
            ))
        }
        return albums
    }

    public func assets(matching criteria: PhotoSearchCriteria) async throws -> [PhotoAsset] {
        try await ensureAuthorized()
        let options = PHFetchOptions()
        var predicates: [NSPredicate] = []
        if let start = criteria.startDate {
            predicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
        }
        if let end = criteria.endDate {
            predicates.append(NSPredicate(format: "creationDate <= %@", end as NSDate))
        }
        if let type = criteria.mediaType {
            predicates.append(NSPredicate(format: "mediaType == %d", Self.phMediaType(type).rawValue))
        }
        if criteria.favoritesOnly {
            predicates.append(NSPredicate(format: "favorite == YES"))
        }
        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = criteria.limit

        let fetch: PHFetchResult<PHAsset>
        if let albumId = criteria.albumId {
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId], options: nil
            ).firstObject else {
                throw PhotoServiceError.notFound("album \(albumId)")
            }
            fetch = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            fetch = PHAsset.fetchAssets(with: options)
        }
        var out: [PhotoAsset] = []
        for i in 0..<fetch.count {
            out.append(Self.photoAsset(from: fetch.object(at: i)))
        }
        return out
    }

    public func asset(id: String) async throws -> PhotoAsset? {
        try await ensureAuthorized()
        guard let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        return Self.photoAsset(from: phAsset)
    }

    public func assets(ids: [String]) async throws -> [PhotoAsset] {
        try await ensureAuthorized()
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var out: [PhotoAsset] = []
        for i in 0..<fetch.count {
            out.append(Self.photoAsset(from: fetch.object(at: i)))
        }
        return out
    }

    // MARK: - Mapping

    /// Maps a `PHAsset` to the library's value type. Title, description,
    /// and keywords stay `nil` — PhotoKit does not expose them; the
    /// service hydrates them via AppleScript when asked for one asset.
    static func photoAsset(from asset: PHAsset) -> PhotoAsset {
        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first { $0.type == .photo || $0.type == .video } ?? resources.first
        return PhotoAsset(
            id: asset.localIdentifier,
            originalFilename: primary?.originalFilename,
            creationDate: asset.creationDate,
            mediaType: Self.mediaType(from: asset.mediaType),
            isFavorite: asset.isFavorite,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude
        )
    }

    static func mediaType(from ph: PHAssetMediaType) -> PhotoMediaType {
        switch ph {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        default: return .unknown
        }
    }

    static func phMediaType(_ type: PhotoMediaType) -> PHAssetMediaType {
        switch type {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        case .unknown: return .unknown
        }
    }

    // MARK: - Writes (implemented in later tasks)

    public func exportOriginals(ids: [String], to directory: URL) async throws -> [URL] {
        fatalError("implemented in Task 10")
    }

    public func imageData(id: String, maxDimension: Int) async throws -> Data {
        fatalError("implemented in Task 10")
    }

    public func createAlbum(title: String) async throws -> PhotoAlbum {
        fatalError("implemented in Task 11")
    }

    public func deleteAlbum(id: String) async throws {
        fatalError("implemented in Task 11")
    }

    public func add(ids: [String], toAlbum albumId: String) async throws {
        fatalError("implemented in Task 11")
    }

    public func remove(ids: [String], fromAlbum albumId: String) async throws {
        fatalError("implemented in Task 11")
    }

    public func setFavorite(id: String, _ isFavorite: Bool) async throws {
        fatalError("implemented in Task 11")
    }

    public func importFiles(urls: [URL], toAlbum albumId: String?) async throws -> [PhotoAsset] {
        fatalError("implemented in Task 11")
    }
}
```

- [ ] **Step 2: Verify build and tests**

Run: `swift build && swift test`
Expected: build succeeds (fix any strict-concurrency diagnostics by keeping all `PHAsset`/`PHFetchResult` usage inside single method bodies — never store them or pass them across `await` boundaries); all unit tests still pass.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add PhotoKitStore authorization and read operations"
```

---

### Task 10: PhotoKitStore — export and imageData

**Files:**
- Modify: `Sources/PhotosAutomation/PhotoKitStore.swift` (replace the two Task-10 `fatalError` stubs)

**Interfaces:**
- Consumes: Task 9's store.
- Produces: working `exportOriginals(ids:to:)` and `imageData(id:maxDimension:)`.

- [ ] **Step 1: Replace the `exportOriginals` and `imageData` stubs**

```swift
    public func exportOriginals(ids: [String], to directory: URL) async throws -> [URL] {
        try await ensureAuthorized()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for id in ids {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
                throw PhotoServiceError.notFound("asset \(id)")
            }
            let resources = PHAssetResource.assetResources(for: asset)
            guard let resource = resources.first(where: { $0.type == .photo || $0.type == .video })
                ?? resources.first
            else {
                throw PhotoServiceError.operationFailed("asset \(id) has no exportable resource")
            }
            let destination = Self.availableURL(in: directory, filename: resource.originalFilename)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(
                    for: resource, toFile: destination, options: options
                ) { error in
                    if let error {
                        c.resume(throwing: PhotoServiceError.operationFailed(error.localizedDescription))
                    } else {
                        c.resume()
                    }
                }
            }
            written.append(destination)
        }
        return written
    }

    public func imageData(id: String, maxDimension: Int) async throws -> Data {
        try await ensureAuthorized()
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw PhotoServiceError.notFound("asset \(id)")
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // handler fires exactly once
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        let target = CGSize(width: maxDimension, height: maxDimension)
        // Encode to JPEG inside the callback so only Sendable Data crosses
        // the continuation (NSImage is not Sendable).
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            PHImageManager.default().requestImage(
                for: asset, targetSize: target, contentMode: .aspectFit, options: options
            ) { image, info in
                guard let image else {
                    let message = (info?[PHImageErrorKey] as? NSError)?.localizedDescription
                        ?? "image request failed"
                    c.resume(throwing: PhotoServiceError.operationFailed(message))
                    return
                }
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
                else {
                    c.resume(throwing: PhotoServiceError.operationFailed("could not encode JPEG for \(id)"))
                    return
                }
                c.resume(returning: jpeg)
            }
        }
    }

    /// Returns a URL in `directory` for `filename`, appending ` (n)` before
    /// the extension when the name is already taken.
    static func availableURL(in directory: URL, filename: String) -> URL {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: filename).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }
```

Also add `import AppKit` at the top of the file (for `NSImage`/`NSBitmapImageRep`).

- [ ] **Step 2: Add a unit test for the pure helper** — append to `Tests/PhotosAutomationTests/PhotoServiceOrganizeTests.swift`

```swift
@Suite struct AvailableURLTests {
    @Test func dedupesExistingFilenames() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-automation-dedupe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = PhotoKitStore.availableURL(in: dir, filename: "IMG_1.HEIC")
        #expect(first.lastPathComponent == "IMG_1.HEIC")
        try Data().write(to: first)

        let second = PhotoKitStore.availableURL(in: dir, filename: "IMG_1.HEIC")
        #expect(second.lastPathComponent == "IMG_1 (1).HEIC")
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift build && swift test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add PhotoKitStore original export and resized JPEG rendition"
```

---

### Task 11: PhotoKitStore — writes (albums, favorite, import)

**Files:**
- Create: `Sources/PhotosAutomation/Locked.swift`
- Modify: `Sources/PhotosAutomation/PhotoKitStore.swift` (replace remaining `fatalError` stubs)

**Interfaces:**
- Consumes: Tasks 9–10.
- Produces: complete `PhotoKitStore`. After this task `grep -rn "fatalError" Sources/` must return nothing.

- [ ] **Step 1: Write `Sources/PhotosAutomation/Locked.swift`**

```swift
import Foundation

/// A minimal lock-guarded box for smuggling results out of PhotoKit's
/// `performChanges` closure, which runs on an arbitrary queue and is
/// `@Sendable` under Swift 6.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
```

- [ ] **Step 2: Replace the remaining stubs in `PhotoKitStore.swift`** (also add `import UniformTypeIdentifiers` at the top)

```swift
    // MARK: - Writes

    /// Runs a PhotoKit change block, translating failures to
    /// ``PhotoServiceError/operationFailed(_:)``.
    private func performChanges(_ block: @escaping @Sendable () -> Void) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges(block)
        } catch {
            throw PhotoServiceError.operationFailed(error.localizedDescription)
        }
    }

    public func createAlbum(title: String) async throws -> PhotoAlbum {
        try await ensureAuthorized()
        let createdId = Locked<String?>(nil)
        try await performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            createdId.value = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = createdId.value,
              let collection = PHAssetCollection.fetchAssetCollections(
                  withLocalIdentifiers: [id], options: nil
              ).firstObject
        else {
            throw PhotoServiceError.operationFailed("album creation returned no identifier")
        }
        return PhotoAlbum(
            id: collection.localIdentifier,
            title: collection.localizedTitle ?? title,
            assetCount: 0
        )
    }

    public func deleteAlbum(id: String) async throws {
        try await ensureAuthorized()
        guard PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            .firstObject != nil
        else {
            throw PhotoServiceError.notFound("album \(id)")
        }
        try await performChanges {
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
            PHAssetCollectionChangeRequest.deleteAssetCollections(collections)
        }
    }

    public func add(ids: [String], toAlbum albumId: String) async throws {
        try await ensureAuthorized()
        try ensureAssetsExist(ids)
        try ensureAlbumExists(albumId)
        try await performChanges {
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId], options: nil
            ).firstObject,
                let request = PHAssetCollectionChangeRequest(for: collection)
            else { return }
            request.addAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    }

    public func remove(ids: [String], fromAlbum albumId: String) async throws {
        try await ensureAuthorized()
        try ensureAssetsExist(ids)
        try ensureAlbumExists(albumId)
        try await performChanges {
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [albumId], options: nil
            ).firstObject,
                let request = PHAssetCollectionChangeRequest(for: collection)
            else { return }
            request.removeAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
        }
    }

    public func setFavorite(id: String, _ isFavorite: Bool) async throws {
        try await ensureAuthorized()
        try ensureAssetsExist([id])
        try await performChanges {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
            else { return }
            PHAssetChangeRequest(for: asset).isFavorite = isFavorite
        }
    }

    public func importFiles(urls: [URL], toAlbum albumId: String?) async throws -> [PhotoAsset] {
        try await ensureAuthorized()
        if let albumId {
            try ensureAlbumExists(albumId)
        }
        let createdIds = Locked<[String]>([])
        try await performChanges {
            var placeholders: [PHObjectPlaceholder] = []
            for url in urls {
                let isVideo = UTType(filenameExtension: url.pathExtension)?
                    .conforms(to: .movie) ?? false
                let request = isVideo
                    ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                if let placeholder = request?.placeholderForCreatedAsset {
                    placeholders.append(placeholder)
                }
            }
            if let albumId,
               let collection = PHAssetCollection.fetchAssetCollections(
                   withLocalIdentifiers: [albumId], options: nil
               ).firstObject,
               let albumRequest = PHAssetCollectionChangeRequest(for: collection) {
                albumRequest.addAssets(placeholders as NSArray)
            }
            createdIds.value = placeholders.map(\.localIdentifier)
        }
        guard createdIds.value.count == urls.count else {
            throw PhotoServiceError.operationFailed(
                "imported \(createdIds.value.count) of \(urls.count) files — unsupported format?"
            )
        }
        return try await assets(ids: createdIds.value)
    }

    // MARK: - Existence checks

    /// Throws ``PhotoServiceError/notFound(_:)`` when any id is unknown.
    private func ensureAssetsExist(_ ids: [String]) throws {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard fetch.count == ids.count else {
            var found = Set<String>()
            for i in 0..<fetch.count {
                found.insert(fetch.object(at: i).localIdentifier)
            }
            let missing = ids.filter { !found.contains($0) }
            throw PhotoServiceError.notFound("asset(s) \(missing.joined(separator: ", "))")
        }
    }

    /// Throws ``PhotoServiceError/notFound(_:)`` when the album is unknown.
    private func ensureAlbumExists(_ albumId: String) throws {
        guard PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil)
            .firstObject != nil
        else {
            throw PhotoServiceError.notFound("album \(albumId)")
        }
    }
```

- [ ] **Step 3: Verify no stubs remain**

Run: `grep -rn "fatalError" Sources/ || echo CLEAN`
Expected: `CLEAN`

- [ ] **Step 4: Build and test**

Run: `swift build && swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add PhotoKitStore album, favorite, and import writes"
```

---

### Task 12: Integration test suite

**Files:**
- Create: `Tests/PhotosAutomationTests/PhotoServiceIntegrationTests.swift`

**Interfaces:**
- Consumes: the whole library.
- Produces: an env-gated end-to-end suite. Not run in CI; run locally with `PHOTOS_AUTOMATION_INTEGRATION=1 swift test`.

Key constraints this suite must respect:
- `.serialized` — it uses `NSAppleScriptRunner` (non-reentrant in test bundles) and mutates one shared library.
- All created albums use the `PhotosAutomationTests-` prefix; each test cleans prior runs' albums first (crash-safe cleanup by prefix).
- **Assets cannot be deleted programmatically without a blocking dialog** — the imported 1×1 PNG stays in the library. This is documented in the README (Task 13).
- The title-roundtrip test is the canary for the AppleScript-id ↔ `localIdentifier` equivalence assumption. If it fails with "Photos got an error: Can't get media item id …", the id formats differ and the metadata scripts need an id-mapping helper — stop and investigate rather than papering over.

- [ ] **Step 1: Write `Tests/PhotosAutomationTests/PhotoServiceIntegrationTests.swift`**

```swift
import Foundation
import Testing
@testable import PhotosAutomation

/// End-to-end tests against the user's real Photos library.
///
/// Requires Photos access for the test binary (macOS prompts on first
/// run) and Automation permission for Photos (for the AppleScript paths).
///
/// **Opt-in**: set `PHOTOS_AUTOMATION_INTEGRATION=1` before `swift test`.
/// Unset, every test here is skipped — keeping CI deterministic and
/// permission-prompt free.
///
/// Cleanup model: albums created here are uniquely prefixed and deleted
/// (album deletion needs no confirmation dialog). The imported 1×1 test
/// PNG cannot be deleted programmatically — PhotoKit asset deletion always
/// shows a blocking dialog — so it stays in the library.
@Suite("PhotoService integration", .serialized)
struct PhotoServiceIntegrationTests {
    static let enabledTrait: any TestTrait = .disabled(
        if: ProcessInfo.processInfo.environment["PHOTOS_AUTOMATION_INTEGRATION"] != "1",
        "set PHOTOS_AUTOMATION_INTEGRATION=1 to run against the real Photos library"
    )

    /// Album-name prefix for test artifacts; prior-run leftovers are
    /// deleted by prefix match.
    static let albumPrefix = "PhotosAutomationTests"

    static func makeService() -> PhotoService {
        PhotoService(store: PhotoKitStore(), runner: NSAppleScriptRunner())
    }

    /// Deletes every album left over from prior (possibly crashed) runs.
    static func cleanUpPriorRuns() async {
        let store = PhotoKitStore()
        guard let albums = try? await store.listAlbums() else { return }
        for album in albums where album.title.hasPrefix(albumPrefix) {
            try? await store.deleteAlbum(id: album.id)
        }
    }

    /// Writes a 1×1 PNG to a temp file and returns its URL.
    static func writeTestPNG() throws -> URL {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(albumPrefix)-\(UUID().uuidString).png")
        try Data(base64Encoded: base64)!.write(to: url)
        return url
    }

    @Test("list albums does not throw", Self.enabledTrait)
    func listAlbums() async throws {
        _ = try await Self.makeService().listAlbums()
    }

    @Test("structured search returns limited results", Self.enabledTrait)
    func structuredSearch() async throws {
        let results = try await Self.makeService()
            .search(criteria: PhotoSearchCriteria(limit: 5))
        #expect(results.count <= 5)
    }

    @Test("end-to-end: import, album, favorite, metadata, rendition, export", Self.enabledTrait)
    func endToEnd() async throws {
        await Self.cleanUpPriorRuns()
        let service = Self.makeService()
        let store = PhotoKitStore()

        // Import a 1×1 PNG.
        let png = try Self.writeTestPNG()
        defer { try? FileManager.default.removeItem(at: png) }
        let imported = try await service.importFiles(urls: [png])
        try #require(imported.count == 1)
        let assetId = imported[0].id

        // Create a uniquely named album and add the asset.
        let albumTitle = "\(Self.albumPrefix)-\(UUID().uuidString.prefix(8))"
        let album = try await service.createAlbum(title: albumTitle)
        defer { Task { try? await store.deleteAlbum(id: album.id) } }
        try await service.add(ids: [assetId], toAlbum: album.id)
        let inAlbum = try await service.listAssets(albumId: album.id)
        #expect(inAlbum.map(\.id) == [assetId])

        // Favorite round-trip.
        try await service.setFavorite(id: assetId, true)
        let favorited = try await store.asset(id: assetId)
        #expect(favorited?.isFavorite == true)
        try await service.setFavorite(id: assetId, false)

        // Title round-trip — the canary for AppleScript-id == localIdentifier.
        let title = "PhotosAutomation test \(UUID().uuidString.prefix(8))"
        try await service.setTitle(id: assetId, title)
        let hydrated = try await service.asset(id: assetId)
        #expect(hydrated.title == title)

        // Keywords round-trip.
        try await service.setKeywords(id: assetId, ["photosautomation-test"])
        let keyworded = try await service.asset(id: assetId)
        #expect(keyworded.keywords == ["photosautomation-test"])

        // In-memory rendition.
        let jpeg = try await service.imageData(id: assetId, maxDimension: 64)
        #expect(!jpeg.isEmpty)

        // Original export.
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.albumPrefix)-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: exportDir) }
        let exported = try await service.exportOriginals(ids: [assetId], to: exportDir)
        try #require(exported.count == 1)
        #expect(FileManager.default.fileExists(atPath: exported[0].path))

        // Remove from album, then clean up the album.
        try await service.remove(ids: [assetId], fromAlbum: album.id)
        let afterRemove = try await service.listAssets(albumId: album.id)
        #expect(afterRemove.isEmpty)
        try await store.deleteAlbum(id: album.id)
    }

    @Test("free-text search does not throw", Self.enabledTrait)
    func freeTextSearch() async throws {
        // Fresh imports may not be indexed yet, so assert only that the
        // call succeeds — not that it finds anything.
        _ = try await Self.makeService().searchText("test", limit: 5)
    }
}
```

- [ ] **Step 2: Verify the gate — plain `swift test` skips the suite**

Run: `swift test`
Expected: PASS with integration tests reported as skipped; no permission prompts.

- [ ] **Step 3: Run the integration suite for real** (requires Photos + Automation permission for the terminal; will prompt on first run)

Run: `PHOTOS_AUTOMATION_INTEGRATION=1 swift test --filter PhotoServiceIntegrationTests --filter NSAppleScriptRunnerTests`
Expected: PASS. If the title round-trip fails with a "Can't get media item id" AppleScript error, STOP — the AppleScript-id assumption is wrong; investigate the actual id format (`osascript -e 'tell application "Photos" to get id of media item 1'`) and add an id-normalization helper to the script builders before proceeding.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test: add env-gated integration suite against the real Photos library"
```

---

### Task 13: Repo scaffolding — README, CLAUDE.md, CI, release automation

**Files:**
- Create: `README.md`
- Create: `CLAUDE.md`
- Create: `VERSION`
- Create: `CHANGELOG.md`
- Create: `release-please-config.json`
- Create: `.release-please-manifest.json`
- Create: `.github/dependabot.yml`
- Create: `.github/release.yml`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release-please.yml`
- Create: `.github/workflows/auto-merge.yml`
- Create: `.github/workflows/pr-auto-review.yml`
- Create: `.github/workflows/claude.yml`

**Interfaces:**
- Consumes: the finished library (README documents the real API).
- Produces: a repo ready for GitHub with the standard chrischall pipeline.

- [ ] **Step 1: Copy the five workflow files, dependabot config, and release-notes config verbatim from the sibling** — they are repo-agnostic stubs:

```bash
mkdir -p .github/workflows
cp ~/git/swift-notes-automation/.github/workflows/ci.yml .github/workflows/ci.yml
cp ~/git/swift-notes-automation/.github/workflows/release-please.yml .github/workflows/release-please.yml
cp ~/git/swift-notes-automation/.github/workflows/auto-merge.yml .github/workflows/auto-merge.yml
cp ~/git/swift-notes-automation/.github/workflows/pr-auto-review.yml .github/workflows/pr-auto-review.yml
cp ~/git/swift-notes-automation/.github/workflows/claude.yml .github/workflows/claude.yml
cp ~/git/swift-notes-automation/.github/dependabot.yml .github/dependabot.yml
cp ~/git/swift-notes-automation/.github/release.yml .github/release.yml
```

Then verify none of them embeds the string `notes`: `grep -ril notes .github/ || echo CLEAN` → expected `CLEAN`.

- [ ] **Step 2: Write `release-please-config.json`**

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "packages": {
    ".": {
      "package-name": "swift-photos-automation",
      "release-type": "simple",
      "include-v-in-tag": true,
      "include-component-in-tag": false,
      "changelog-sections": [
        { "type": "feat", "section": "Features" },
        { "type": "fix", "section": "Bug Fixes" },
        { "type": "perf", "section": "Performance" },
        { "type": "revert", "section": "Reverts" },
        { "type": "refactor", "section": "Refactor" },
        { "type": "docs", "section": "Documentation" },
        { "type": "test", "section": "Tests", "hidden": true },
        { "type": "build", "section": "Build", "hidden": true },
        { "type": "ci", "section": "CI", "hidden": true },
        { "type": "chore", "section": "Chores", "hidden": true }
      ]
    }
  }
}
```

- [ ] **Step 3: Write `.release-please-manifest.json`, `VERSION`, `CHANGELOG.md`**

`.release-please-manifest.json`:
```json
{
  ".": "0.1.0"
}
```

`VERSION`:
```
0.1.0
```

`CHANGELOG.md`:
```markdown
# Changelog

## 0.1.0 (2026-07-02)

### Features

- Initial release: hybrid PhotoKit + AppleScript library for Apple Photos —
  structured and free-text search, metadata reads/writes (titles,
  descriptions, keywords, favorites), original export, in-memory JPEG
  renditions, album management, and import.
```

- [ ] **Step 4: Write `README.md`**

```markdown
# PhotosAutomation

[![CI](https://github.com/chrischall/swift-photos-automation/actions/workflows/ci.yml/badge.svg)](https://github.com/chrischall/swift-photos-automation/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fchrischall%2Fswift-photos-automation%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/chrischall/swift-photos-automation)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fchrischall%2Fswift-photos-automation%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/chrischall/swift-photos-automation)
[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Swift library for driving the Apple Photos library on macOS. One
`PhotoService` facade over two complementary transports:

- **PhotoKit** — structured search (dates, media type, favorites,
  albums), asset metadata, original export, in-memory JPEG renditions,
  album management, favorites, and import.
- **AppleScript** — the operations PhotoKit does not expose: writing
  titles, descriptions, and keywords, plus free-text search through
  Photos' own search engine (matches titles, keywords, and detected
  content).

Platform: **macOS 14+**. Pure Swift 6 with strict concurrency. Zero
external dependencies.

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/chrischall/swift-photos-automation.git", from: "0.1.0"),
]
```

## Quickstart

```swift
import PhotosAutomation

let service = PhotoService(store: PhotoKitStore())

// Newest 20 favorites
let favorites = try await service.search(
    criteria: PhotoSearchCriteria(favoritesOnly: true, limit: 20)
)

// Free-text search (titles, keywords, detected content)
let beach = try await service.searchText("beach sunset", limit: 10)

// Full metadata for one asset (titles/keywords hydrated via AppleScript)
let asset = try await service.asset(id: beach[0].id)

// In-memory JPEG scaled to 1024px — e.g. for base64 MCP content
let jpeg = try await service.imageData(id: asset.id)

// Organize
let album = try await service.createAlbum(title: "Beach Trips")
try await service.add(ids: [asset.id], toAlbum: album.id)
try await service.setTitle(id: asset.id, "Golden hour")

// Export originals (photos and videos)
let files = try await service.exportOriginals(
    ids: [asset.id], to: URL(fileURLWithPath: "/tmp/photos-export")
)

// Import
let imported = try await service.importFiles(
    urls: [URL(fileURLWithPath: "/tmp/new.jpg")], albumId: album.id
)
```

## API

| Operation | Method | Transport |
|---|---|---|
| List albums | `listAlbums()` | PhotoKit |
| List assets | `listAssets(albumId:limit:)` | PhotoKit |
| Structured search | `search(criteria:)` | PhotoKit |
| Free-text search | `searchText(_:limit:)` | AppleScript + PhotoKit |
| Asset detail | `asset(id:)` | PhotoKit + AppleScript |
| Export originals | `exportOriginals(ids:to:)` | PhotoKit |
| JPEG rendition | `imageData(id:maxDimension:)` | PhotoKit |
| Create album | `createAlbum(title:)` | PhotoKit |
| Add / remove in album | `add(ids:toAlbum:)` / `remove(ids:fromAlbum:)` | PhotoKit |
| Favorite | `setFavorite(id:_:)` | PhotoKit |
| Title / description / keywords | `setTitle` / `setDescription` / `setKeywords` | AppleScript |
| Import | `importFiles(urls:albumId:)` | PhotoKit |

Asset IDs are PhotoKit `localIdentifier`s, which Photos' AppleScript
dictionary exposes identically — one ID works across both transports.

## Capabilities & limits

- **No asset deletion.** PhotoKit deletion always shows a blocking
  system confirmation dialog — useless from a server. Deliberately
  omitted.
- **Titles/descriptions/keywords are AppleScript-only.** PhotoKit cannot
  read or write them. They are `nil` in list/search results and hydrated
  only by `asset(id:)`; hydration is best-effort (stays `nil` if
  Photos.app is unreachable).
- **Smart albums, Live Photo editing, and iCloud shared albums** are out
  of scope.

## Permissions

Two TCC grants, both prompted on first use:

1. **Photos library access** (full access) for the PhotoKit paths.
2. **Automation → Photos** for the AppleScript paths (metadata writes,
   free-text search).

Bare executables need an embedded Info.plist with
`NSPhotoLibraryUsageDescription` to request Photos access (see
apple-swift-mcp's `-sectcreate __TEXT __info_plist` linker flags).

## Testing

```bash
swift test                                  # unit tests only — no prompts
PHOTOS_AUTOMATION_INTEGRATION=1 swift test  # + live suites (real library)
```

The integration suite creates uniquely prefixed albums and deletes them
afterwards. The one imported test image (a 1×1 PNG) **stays in your
library** — assets can't be deleted programmatically without a
confirmation dialog.

## License

MIT
```

- [ ] **Step 5: Write `CLAUDE.md`**

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Swift 6 library exposing the Apple Photos library on macOS through one `PhotoService` facade over two transports:

- **PhotoKit** (`PhotoKitStore: PhotoLibraryStore`) — structured search, metadata, export, in-memory JPEG renditions, albums, favorites, import.
- **AppleScript** (`NSAppleScriptRunner: AppleScriptRunner`) — only what PhotoKit cannot do: writing titles/descriptions/keywords and free-text search (`search for`).

Target: macOS 14+. Zero external dependencies. Strict concurrency is on (all public types are `Sendable`).

## Commands

```bash
swift build                                          # debug build
swift test                                           # pure-Swift tests only — live suites are opt-in
swift test --filter PhotoServiceReadTests            # single suite
PHOTOS_AUTOMATION_INTEGRATION=1 swift test           # + live suites (real Photos library)
swiftformat . --lint                                 # lint (config in .swiftformat)
```

- Live suites (`PhotoServiceIntegrationTests`, `NSAppleScriptRunnerTests`) are gated by `PHOTOS_AUTOMATION_INTEGRATION=1` via `.disabled(if:)` traits. They need **Photos library access** and **Automation → Photos** permission for the test binary. Without the env var they're skipped, so CI stays deterministic and prompt-free.

## Architecture

- `PhotoService` (public API, `Sources/PhotosAutomation/PhotoService.swift`) validates inputs, orchestrates the two injected transports, and owns all AppleScript **generation** (static script builders) and **parsing** (static parse helpers) — both unit-testable without AppleScript running.
- `PhotoLibraryStore` protocol isolates PhotoKit; `FakePhotoLibraryStore` (test target) is the unit-test double. `PhotoKitStore` is verified by the integration suite, not unit tests — keep logic there thin and push anything parseable/decidable into `PhotoService` statics.
- `AppleScriptRunner`/`NSAppleScriptRunner` are copied from swift-notes-automation — treat as vendored; don't redesign.

### Non-obvious constraints to respect

1. **Asset IDs**: PhotoKit `localIdentifier` == AppleScript `media item id`. The integration test's title round-trip is the canary; if it breaks on a macOS update, add id normalization in the script builders.
2. **Every string interpolated into AppleScript must go through `PhotoService.escapeForAppleScript`** (backslashes before quotes).
3. **`NSAppleScript` is non-reentrant inside test bundles** — any suite that runs it live carries `.serialized` and the env-var gate (error -1751 flakes otherwise).
4. **No asset deletion, ever** — PhotoKit deletion shows a blocking dialog. Integration tests clean up *albums* only; the imported 1×1 test PNG stays in the library (documented in README).
5. **`performChanges` closures are `@Sendable` and run on an arbitrary queue** — fetch PH objects *inside* the closure; smuggle results out via `Locked<T>`, never captured vars.
6. **Metadata hydration is best-effort**: `asset(id:)` swallows AppleScript failures and leaves title/description/keywords `nil`. Metadata *writes* propagate `AppleScriptError` — consumers catch both error types.

<!-- pr-workflow:v2 -->
## Pull requests & release notes

**Default workflow: branch + PR, even for solo work.** Direct pushes to `main` skip review *and* skip auto-generated release notes — GitHub's `generate_release_notes` (configured in `.github/release.yml`) only picks up merged PRs. Push directly to `main` only when the user explicitly asks for it (e.g. emergency hotfix).

For every PR, apply exactly one label so it lands in the right release-notes section:

| Label                | Section in release notes |
|----------------------|--------------------------|
| `enhancement`        | Features                 |
| `bug`                | Bug Fixes                |
| `security`           | Security                 |
| `refactor`           | Refactor                 |
| `documentation`      | Documentation            |
| `test`               | Tests                    |
| `dependencies`       | Dependencies             |
| `ci` / `github_actions` | CI & Build            |
| *(none / unmatched)* | Other Changes            |
| `ignore-for-release` | Hidden from notes        |

The **PR title MUST be a Conventional Commit**, written user-facing (`fix(scope): …`, `feat(scope): …`), not internal shorthand. Because the repo squash-merges, the PR title *becomes the squash commit's subject line* — the only thing release-please parses to pick the version bump and changelog section. Only `feat` (minor), `fix` (patch), and `!`/`BREAKING CHANGE` (major) cut a release; `perf`/`refactor`/`docs` show in the changelog without bumping; `ci`/`test`/`build`/`chore` are recognised but hidden (see `release-please-config.json` → `changelog-sections`). A title without a conventional type is invisible to release-please — no bump, no changelog line. Prefixes in *individual commits* don't help; squash keeps only the title.

Open with `gh pr create --label <label>` (or `--label ignore-for-release` for chores not worth a line). **Don't run `gh pr merge` yourself** — leave merging to the user. The repo is **squash-only** (no merge commit, no rebase), so don't pass `--merge`/`--rebase`.
```

- [ ] **Step 6: Verify build/test still green**

Run: `swift build && swift test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "docs: add README, CLAUDE.md, CI workflows, and release automation"
```

---

### Task 14: Format, final verification, and (user-gated) publish

**Files:**
- Modify: any files swiftformat touches.

**Interfaces:**
- Consumes: everything.
- Produces: a formatted, verified repo. Publishing to GitHub is a **user decision** — ask, don't assume.

- [ ] **Step 1: Install swiftformat if missing and run it**

```bash
which swiftformat || brew install swiftformat
swiftformat .
```

- [ ] **Step 2: Full verification**

Run: `swift build && swift test`
Expected: PASS. If swiftformat changed anything, eyeball the diff (`git diff`) — it must be whitespace/style only.

- [ ] **Step 3: Commit any formatting changes**

```bash
git add -A
git diff --cached --quiet || git commit -m "chore: apply swiftformat"
```

- [ ] **Step 4: Run the integration suite one final time**

Run: `PHOTOS_AUTOMATION_INTEGRATION=1 swift test`
Expected: PASS — full library verified end-to-end.

- [ ] **Step 5: ASK THE USER before publishing.** Creating the GitHub repo is outward-facing. Confirm: repo name `chrischall/swift-photos-automation`, public, then:

```bash
gh repo create chrischall/swift-photos-automation --public --source=. --push
git tag v0.1.0 && git push origin v0.1.0
```

The `v0.1.0` tag is what lets apple-swift-mcp consume the package with `from: "0.1.0"`. Follow-up work (separate effort, in apple-swift-mcp): add `NSPhotoLibraryUsageDescription` to its embedded Info.plist, add the package dependency, write `PhotoTool`, register it in `AppleMCPMain.swift`.
```

---

## Self-Review Notes

- **Spec coverage:** read/search (Tasks 5–6, 9), export both forms (Tasks 8, 10), organize (Tasks 7–8, 11), import (Tasks 8, 11), errors (Task 3), testing incl. cleanup caveat (Tasks 2–12), permissions docs (Task 13), scaffolding (Tasks 1, 13). `deleteAlbum` is an addition beyond the spec's public API — it exists on the store (not `PhotoService`) solely for integration-test cleanup, which the spec's testing section requires.
- **Type consistency:** `PhotoService` methods match the spec's API list; `itemDescription` (not `description`, which collides with `CustomStringConvertible`) is used consistently.
- **Known risk, handled explicitly:** the AppleScript-id == localIdentifier assumption has a designated canary test and a stop-and-investigate instruction (Task 12, Step 3).
