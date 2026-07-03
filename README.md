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

- **No deletion, of assets or albums.** PhotoKit deletion — of assets
  *and* of albums — always shows a blocking system confirmation dialog,
  which would hang an unattended caller. Deliberately omitted.
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
swift test                                    # unit tests only — no prompts
PHOTOS_AUTOMATION_INTEGRATION=1 swift test    # + live PhotoKit suites (real library)
PHOTOS_AUTOMATION_INTEGRATION=1 \
PHOTOS_AUTOMATION_APPLESCRIPT=1 swift test    # + live AppleScript-to-Photos suites
```

Two opt-in env vars gate the live suites, so `swift test` alone stays
deterministic and prompt-free:

- `PHOTOS_AUTOMATION_INTEGRATION=1` runs the PhotoKit-only integration
  tests (import, albums, favorites, renditions, export) against your
  real Photos library. Needs Photos library access, prompted on first
  run.
- `PHOTOS_AUTOMATION_APPLESCRIPT=1` (on top of the above) additionally
  runs the AppleScript-to-Photos tests — the metadata round-trip
  (title/keywords) and free-text search. These need **Automation →
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
