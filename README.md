# PhotosAutomation

[![CI](https://github.com/chrischall/swift-photos-automation/actions/workflows/ci.yml/badge.svg)](https://github.com/chrischall/swift-photos-automation/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fchrischall%2Fswift-photos-automation%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/chrischall/swift-photos-automation)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fchrischall%2Fswift-photos-automation%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/chrischall/swift-photos-automation)
[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Swift library for driving the Apple Photos library on macOS. One
`PhotoService` facade over two complementary transports:

- **PhotoKit** — structured search (dates, media type, favorites,
  albums), asset metadata including descriptions, keywords, star ratings
  and file sizes (read and write), original export, in-memory JPEG
  renditions, album management, favorites, and import.
- **AppleScript** — the operations PhotoKit does not expose: titles, plus
  free-text search through Photos' own search engine (matches titles,
  keywords, and detected content).

Platform: **macOS 27.2+** (built with Swift 6.4). Pure Swift 6 with strict
concurrency. Zero external dependencies.

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

// Full metadata for one asset (the title is read via AppleScript)
let asset = try await service.asset(id: beach[0].id)

// In-memory JPEG scaled to 1024px — e.g. for base64 MCP content
let jpeg = try await service.imageData(id: asset.id)

// Organize
let album = try await service.createAlbum(title: "Beach Trips")
try await service.add(ids: [asset.id], toAlbum: album.id)
try await service.setTitle(id: asset.id, "Golden hour")

// Export originals (photos and videos)
let files = try await service.exportOriginals(
    ids: [asset.id], to: URL(filePath: "/tmp/photos-export")
)

// Import
let imported = try await service.importFiles(
    urls: [URL(filePath: "/tmp/new.jpg")], albumId: album.id
)
```

## API

| Operation | Method | Transport |
|---|---|---|
| List albums | `listAlbums()` | PhotoKit |
| List assets | `listAssets(albumId:limit:)` | PhotoKit |
| Structured search | `search(criteria:)` | PhotoKit |
| Free-text search | `searchText(_:limit:)` | AppleScript + PhotoKit |
| Asset detail | `asset(id:)` | PhotoKit + AppleScript (title only) |
| Export originals | `exportOriginals(ids:to:)` | PhotoKit |
| JPEG rendition | `imageData(id:maxDimension:)` | PhotoKit |
| Create album | `createAlbum(title:)` | PhotoKit |
| Add / remove in album | `add(ids:toAlbum:)` / `remove(ids:fromAlbum:)` | PhotoKit |
| Favorite | `setFavorite(id:_:)` | PhotoKit |
| Title | `setTitle(id:_:)` | AppleScript |
| Description / keywords / rating | `setDescription` / `setKeywords` / `setRating` | PhotoKit |
| Live Photo playback on/off | `setLivePhotoPlayback(id:enabled:)` | PhotoKit |
| Import | `importFiles(urls:albumId:)` | PhotoKit |
| Copy album (callback or `Subprogress` progress) | `copyAlbum(sourceAlbumId:targetAlbumId:…)` | PhotoKit |

Asset IDs are PhotoKit `localIdentifier`s, which Photos' AppleScript
dictionary exposes identically — one ID works across both transports.

## Errors

Every public `PhotoService` method uses typed throws — `throws(PhotosError)`
— so `catch` binds one enum that still tells every failure apart:

```swift
do {
    try await service.setTitle(id: id, "Golden hour")
} catch {
    switch error {                      // `error` is a PhotosError
    case let .service(e): print(e)      // PhotoServiceError: validation / PhotoKit
    case let .appleScript(e): print(e)  // AppleScriptError: titles, free-text search
    case .cancelled: break              // the store reported task cancellation
    }
}
```

`error.localizedDescription` is the wrapped error's, unchanged.
`error.serviceError` / `error.appleScriptError` unwrap one side without a
`switch`. `AppleScriptRunner.run(source:)` is `throws(AppleScriptError)`.

### Migrating from 1.x (breaking)

1. **Catch `PhotosError`, not the two types separately.** Replace
   `catch let e as PhotoServiceError { … } catch let e as AppleScriptError { … }`
   around `PhotoService` calls with one `catch let e as PhotosError` (or, in
   a `do` block containing only `PhotoService` calls, a bare `catch`) and
   `switch` on `.service(e)` / `.appleScript(e)` / `.cancelled` — the inner
   `PhotoServiceError` and `AppleScriptError` cases are unchanged.
   `#expect(throws: PhotoServiceError.notFound("x"))` becomes
   `#expect(throws: PhotosError.service(.notFound("x")))`.
2. **Custom `AppleScriptRunner`s** must declare
   `func run(source: String) async throws(AppleScriptError) -> String`
   (a non-throwing `run` also conforms). A plain `throws` witness no
   longer compiles.
3. **Custom `PhotoLibraryStore`s need no change** — the protocol keeps
   untyped `throws`. `PhotoServiceError`s they throw arrive as
   `.service(…)`; any other error type arrives as
   `.service(.operationFailed(localizedDescription))`, and
   `CancellationError` as `.cancelled`.

## Capabilities & limits

- **No asset deletion.** PhotoKit asset deletion always shows a blocking
  system confirmation dialog, which would hang an unattended caller.
  Deliberately omitted.
- **Album deletion exists but isn't surfaced through `PhotoService`.**
  `PhotoKitStore.deleteAlbum(id:)` is public for consumers with an
  interactive UI, but it too shows a blocking confirmation dialog, so
  it's intentionally left off the `PhotoService` facade and never used
  by the test suite.
- **Titles are AppleScript-only.** PhotoKit has no title API, so a title is
  `nil` in list/search results and read only by `asset(id:)`, best-effort
  (it stays `nil` if Photos.app is unreachable). Descriptions, keywords,
  ratings, file sizes, `isLivePhoto` and `originalResource` (RAW vs
  compressed, for RAW+JPEG assets) come from PhotoKit and are present
  everywhere.
- **The original resource is read-only.** PhotoKit can switch a RAW+JPEG
  asset's original only by reverting it, which discards the user's edits,
  so the library reports the choice but never changes it.
- **No path confinement by default.** `exportOriginals(ids:to:)` writes
  into any directory it is given and `importFiles(urls:)` reads any file
  the process can reach — the library does no allow-listing. A consumer
  that forwards untrusted paths (e.g. an MCP tool taking model-chosen
  paths) must confine them: enforce its own policy, or pass
  `allowedRoot:`, which refuses any path that resolves (symlinks and `..`
  included) outside that directory before the library is touched.
- **Smart albums and Live Photo editing** (beyond turning playback on or
  off) are out of scope.

## Permissions

Two TCC grants, both prompted on first use:

1. **Photos library access** (full access) for the PhotoKit paths.
2. **Automation → Photos** for the AppleScript paths (titles, free-text
   search).

Bare executables need an embedded Info.plist with
`NSPhotoLibraryUsageDescription` to request Photos access (see
apple-swift-mcp's `-sectcreate __TEXT __info_plist` linker flags).

## Testing

```bash
swift test                                    # unit tests only — no prompts
PHOTOS_AUTOMATION_INTEGRATION=1 swift test    # + live PhotoKit suites (real library)
PHOTOS_AUTOMATION_INTEGRATION=1 \
PHOTOS_AUTOMATION_APPLESCRIPT=1 swift test    # + live AppleScript-to-Photos suites
```

Two opt-in env vars gate the live suites, so `swift test` alone stays
deterministic and prompt-free:

- `PHOTOS_AUTOMATION_INTEGRATION=1` runs the PhotoKit-only integration
  tests (import, albums, favorites, renditions, export, and the
  description/keyword/rating round-trip) against your
  real Photos library. Needs Photos library access, prompted on first
  run. Two tests also need an id: `PHOTOS_LIVE_PHOTO_ID` (an existing
  Live Photo, for the playback toggle) and `PHOTOS_SHARED_SOURCE_ALBUM_ID`
  (a shared album, for the copy tests); without them they return early.
- `PHOTOS_AUTOMATION_APPLESCRIPT=1` (on top of the above) additionally
  runs the AppleScript-to-Photos tests — the title round-trip and
  free-text search. These need **Automation →
  Photos** permission for the test binary, and are unreliable from a
  `swift test` bundle: `NSAppleScript` targeting another app can hang
  waiting on the permission prompt, or flake on reentrancy inside the
  test process. The library's AppleScript paths work fine from a normal
  binary (e.g. apple-swift-mcp) — this caveat is about the test bundle,
  not the code.

**Cleanup model: nothing the integration suite creates is deleted
programmatically.** PhotoKit deletion — of assets *and* of albums —
always shows a blocking confirmation dialog, so the suite deletes
nothing: the one imported test image (a 1×1 PNG) and the
uniquely-named `PhotosAutomationTests-*` album it creates both stay in
your library. Remove them by hand (or leave them — they're harmless).

## License

MIT
